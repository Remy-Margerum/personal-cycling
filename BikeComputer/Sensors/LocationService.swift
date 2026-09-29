import CoreLocation
import CoreMotion
import Foundation
import Observation
import RideKit

/// GPS for position, speed and distance; the barometer (CMAltimeter) for
/// altitude and elevation gain, since GPS altitude is too noisy to sum.
@Observable
final class LocationService: NSObject {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var latestLocation: CLLocation?
    /// Barometric + GPS fused altitude (m), when the device provides it.
    private(set) var absoluteAltitude: Double?
    /// Metres climbed/descended since `startAltitudeTracking`, from the barometer.
    private(set) var relativeAltitude: Double?

    /// Every accepted location is delivered here (recorder + HealthKit route).
    @ObservationIgnored var onLocations: (([CLLocation]) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var wantsUpdates = false
    @ObservationIgnored private let altimeter = CMAltimeter()

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    var hasBarometer: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Starts GPS. Called when the ride screen appears so there's a fix
    /// before you press Start, and kept running in the background while riding.
    func start() {
        wantsUpdates = true
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        else {
            DebugLog.shared.log(.gps, "start requested, waiting for permission (\(manager.authorizationStatus.debugName))")
            return // resumed from locationManagerDidChangeAuthorization
        }
        DebugLog.shared.log(.gps, "start")
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stop() {
        DebugLog.shared.log(.gps, "stop")
        wantsUpdates = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        stopAltitudeTracking()
    }

    func startAltitudeTracking() {
        relativeAltitude = nil
        DebugLog.shared.log(.gps, "altimeter start: relative \(CMAltimeter.isRelativeAltitudeAvailable()), "
            + "absolute \(CMAltimeter.isAbsoluteAltitudeAvailable()), permission \(CMAltimeter.authorizationStatus().rawValue)")
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                if let error { DebugLog.shared.log(.gps, "relative altitude error: \(error.localizedDescription)") }
                guard let data else { return }
                self?.relativeAltitude = data.relativeAltitude.doubleValue
            }
        }
        if CMAltimeter.isAbsoluteAltitudeAvailable() {
            altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, error in
                if let error { DebugLog.shared.log(.gps, "absolute altitude error: \(error.localizedDescription)") }
                guard let data else { return }
                self?.absoluteAltitude = data.altitude
            }
        }
    }

    func stopAltitudeTracking() {
        altimeter.stopRelativeAltitudeUpdates()
        altimeter.stopAbsoluteAltitudeUpdates()
    }

    /// Best available altitude for the ride record.
    var altitude: Double? {
        if let absoluteAltitude { return absoluteAltitude }
        guard let location = latestLocation, location.verticalAccuracy >= 0 else { return nil }
        return location.altitude
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        let precise = manager.accuracyAuthorization == .fullAccuracy ? "precise" : "approximate (distance will be wrong)"
        DebugLog.shared.log(.gps, "permission \(manager.authorizationStatus.debugName), \(precise)")
        if wantsUpdates { start() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Ignore cached fixes delivered on startup.
        let fresh = locations.filter { abs($0.timestamp.timeIntervalSinceNow) < 10 && $0.horizontalAccuracy >= 0 }
        if fresh.count < locations.count {
            DebugLog.shared.log(.gps, "dropped \(locations.count - fresh.count) stale or invalid fixes")
        }
        guard let last = fresh.last else { return }
        var previous = latestLocation
        for fix in fresh {
            DebugLog.shared.log(.gps, fix.logLine(after: previous))
            previous = fix
        }
        latestLocation = last
        onLocations?(fresh)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DebugLog.shared.log(.gps, "error: \(error.localizedDescription)")
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        DebugLog.shared.log(.gps, "iOS paused location updates")
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        DebugLog.shared.log(.gps, "iOS resumed location updates")
    }
}

private extension CLAuthorizationStatus {
    var debugName: String {
        switch self {
        case .authorizedAlways: "always"
        case .authorizedWhenInUse: "while using"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not asked yet"
        @unknown default: "status \(rawValue)"
        }
    }
}

private extension CLLocation {
    /// Accuracy, speed and movement, but no coordinates (see DebugLog).
    func logLine(after previous: CLLocation?) -> String {
        var text = "fix ±\(DebugFormat.fixed(horizontalAccuracy, 1)) m"
        text += " speed \(speed >= 0 ? DebugFormat.fixed(speed, 2) : "--") m/s"
        text += " alt \(verticalAccuracy >= 0 ? DebugFormat.fixed(altitude, 1) : "--") ±\(verticalAccuracy >= 0 ? DebugFormat.fixed(verticalAccuracy, 1) : "--") m"
        text += " age \(DebugFormat.fixed(-timestamp.timeIntervalSinceNow, 1)) s"
        if let previous {
            text += " step \(DebugFormat.fixed(distance(from: previous), 1)) m"
            text += " in \(DebugFormat.fixed(timestamp.timeIntervalSince(previous.timestamp), 1)) s"
        }
        return text
    }
}

extension CLLocation {
    var fix: LocationFix {
        LocationFix(timestamp: timestamp, latitude: coordinate.latitude, longitude: coordinate.longitude,
                    horizontalAccuracy: horizontalAccuracy, speed: speed)
    }
}
