import CoreLocation
import Foundation
import Observation
import RideKit

/// Ties the three sensor services together and records one sample per
/// second while riding. Owns the ride lifecycle: start → pause/resume → finish.
@Observable
final class RideRecorder {
    enum State: Equatable { case idle, recording, paused, saving }

    let power: PowerMeterService
    let workout: WorkoutSessionService
    let location: LocationService
    let store: RideStore

    private(set) var state: State = .idle
    private(set) var startDate: Date?
    private(set) var movingTime: TimeInterval = 0
    private(set) var distance: Double = 0
    private(set) var elevationGain: Double = 0
    private(set) var samples: [RideSample] = []
    private(set) var lastError: String?

    /// Current speed in m/s (negative GPS speed is reported as nil).
    var speed: Double? {
        guard let s = location.latestLocation?.speed, s >= 0 else { return nil }
        return s
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var distanceAccumulator = DistanceAccumulator()
    @ObservationIgnored private var elevationAccumulator = ElevationGainAccumulator()
    @ObservationIgnored private var usingBarometer = false

    init(power: PowerMeterService, workout: WorkoutSessionService, location: LocationService, store: RideStore) {
        self.power = power
        self.workout = workout
        self.location = location
        self.store = store
        location.onLocations = { [weak self] locations in self?.handle(locations) }
    }

    // MARK: Lifecycle

    @MainActor
    func start() async {
        guard state == .idle else { return }
        let now = Date()
        do {
            try await workout.start(at: now)
        } catch {
            // Keep recording without HealthKit (no heart rate) rather than not at all.
            lastError = "Apple Health workout didn't start: \(error.localizedDescription)"
            DebugLog.shared.log(.ride, lastError ?? "")
        }
        startDate = now
        movingTime = 0
        distance = 0
        elevationGain = 0
        samples = []
        distanceAccumulator = DistanceAccumulator()
        usingBarometer = location.hasBarometer
        elevationAccumulator = ElevationGainAccumulator(threshold: usingBarometer ? 1 : 4)
        location.start()
        location.startAltitudeTracking()
        DebugLog.shared.log(.ride, "start, elevation from \(usingBarometer ? "barometer" : "GPS altitude")")
        state = .recording
        lastTick = now
        startTimer()
    }

    func pause() {
        guard state == .recording else { return }
        updateMovingTime(now: Date())
        state = .paused
        DebugLog.shared.log(.ride, "pause")
        workout.pause()
    }

    func resume() {
        guard state == .paused else { return }
        distanceAccumulator.breakSegment()
        lastTick = Date()
        state = .recording
        DebugLog.shared.log(.ride, "resume")
        workout.resume()
    }

    @MainActor
    func finish() async {
        guard state == .recording || state == .paused, let startDate else { return }
        if state == .recording { updateMovingTime(now: Date()) }
        state = .saving
        stopTimer()
        location.stopAltitudeTracking()

        let ride = Ride(startDate: startDate, endDate: Date(), movingTime: movingTime,
                        elevationGain: elevationGain, samples: samples)
        DebugLog.shared.log(.ride, "finish: \(samples.count) samples, \(DebugFormat.fixed(distance, 0)) m, "
            + "\(Int(movingTime)) s moving, \(DebugFormat.fixed(elevationGain, 0)) m climbed")
        do {
            try store.save(ride)
        } catch {
            lastError = "Couldn't save ride: \(error.localizedDescription)"
            DebugLog.shared.log(.ride, lastError ?? "")
        }
        do {
            try await workout.finish(ride: ride)
        } catch {
            lastError = "Saved locally, but Apple Health save failed: \(error.localizedDescription)"
            DebugLog.shared.log(.ride, lastError ?? "")
        }
        state = .idle
        self.startDate = nil
    }

    @MainActor
    func discard() {
        DebugLog.shared.log(.ride, "discard")
        stopTimer()
        location.stopAltitudeTracking()
        workout.discard()
        samples = []
        state = .idle
        startDate = nil
    }

    // MARK: Sampling

    private func startTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()
        power.expireStaleReadings(now: now)
        workout.expireStaleReadings(now: now)
        guard state == .recording else { return }
        updateMovingTime(now: now)

        if usingBarometer, let relative = location.relativeAltitude {
            elevationAccumulator.add(altitude: relative)
        } else if !usingBarometer, let altitude = location.altitude {
            elevationAccumulator.add(altitude: altitude)
        }
        elevationGain = elevationAccumulator.gain

        let loc = location.latestLocation
        let fresh = loc.map { now.timeIntervalSince($0.timestamp) < 5 } ?? false
        let sample = RideSample(
            timestamp: now,
            latitude: fresh ? loc?.coordinate.latitude : nil,
            longitude: fresh ? loc?.coordinate.longitude : nil,
            altitude: location.altitude,
            distance: distance,
            speed: fresh ? speed : nil,
            heartRate: workout.heartRate,
            power: power.power,
            cadence: power.cadence.map { Int($0.rounded()) })
        samples.append(sample)
        DebugLog.shared.log(.ride, "sample #\(samples.count) power \(sample.power.map(String.init) ?? "--")"
            + " cadence \(sample.cadence.map(String.init) ?? "--") hr \(sample.heartRate.map(String.init) ?? "--")"
            + " speed \(DebugFormat.fixed(sample.speed, 2)) dist \(DebugFormat.fixed(distance, 1))"
            + " gps \(fresh ? "fresh" : "stale") alt \(DebugFormat.fixed(sample.altitude, 1))"
            + " rel \(DebugFormat.fixed(location.relativeAltitude, 2)) gain \(DebugFormat.fixed(elevationGain, 1))")
    }

    private func updateMovingTime(now: Date) {
        if let lastTick { movingTime += now.timeIntervalSince(lastTick) }
        lastTick = now
    }

    private func handle(_ locations: [CLLocation]) {
        guard state == .recording else { return }
        for location in locations {
            if !distanceAccumulator.add(location.fix) {
                DebugLog.shared.log(.ride, "distance filter rejected fix ±\(DebugFormat.fixed(location.horizontalAccuracy, 1)) m")
            }
        }
        distance = distanceAccumulator.total
        workout.addRoute(locations.filter { $0.horizontalAccuracy <= 20 })
    }
}
