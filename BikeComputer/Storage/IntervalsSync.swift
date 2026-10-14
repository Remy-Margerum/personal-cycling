import Foundation
import Observation
import RideKit
import UIKit

/// Uploads rides to Intervals.icu, which feeds remymargerum.com/cycling on
/// its hourly sync. Each saved ride is queued (unless auto-upload is off in
/// Settings) and retried whenever the app comes to the foreground until it
/// goes through, so a ride finished without signal uploads later. Intervals.icu
/// de-duplicates by file, so retries never create a second activity.
@Observable
final class IntervalsSync {
    static let autoUploadKey = "intervalsAutoUpload"
    static var autoUploadEnabled: Bool { UserDefaults.standard.object(forKey: autoUploadKey) as? Bool ?? true }

    private(set) var log: Intervals.UploadLog
    private(set) var uploading: Set<UUID> = []

    private let store: RideStore
    private let logFile: URL
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(store: RideStore) {
        self.store = store
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        logFile = support.appendingPathComponent("intervals-uploads.json")
        log = (try? Data(contentsOf: logFile)).flatMap { try? JSONDecoder().decode(Intervals.UploadLog.self, from: $0) }
            ?? Intervals.UploadLog()
    }

    func state(of ride: Ride) -> Intervals.UploadState? { log[ride.id] }

    /// Queues a just-saved ride and starts uploading it.
    @MainActor
    func queue(_ ride: Ride) {
        log.queue(ride.id)
        save()
        DebugLog.shared.log(.intervals, "queued ride \(ride.id.uuidString.prefix(8))")
        Task { await upload(ride) }
    }

    /// Uploads every queued or previously failed ride, one at a time.
    @MainActor
    func sync() async {
        let pending = log.pending(among: store.rides.map(\.id))
        guard !pending.isEmpty else { return }
        DebugLog.shared.log(.intervals, "sync: \(pending.count) ride(s) to upload")
        for id in pending {
            guard let ride = store.rides.first(where: { $0.id == id }) else { continue }
            await upload(ride)
        }
    }

    /// Uploads one ride now (also used by History's upload button). A
    /// failure is kept and retried on the next sync.
    @MainActor
    func upload(_ ride: Ride) async {
        guard !uploading.contains(ride.id) else { return }
        log.queue(ride.id)
        guard let apiKey = Keychain.read(Keychain.intervalsAPIKey), !apiKey.isEmpty else {
            record(.failed("Add your Intervals.icu API key in Settings."), for: ride)
            return
        }
        uploading.insert(ride.id)
        beginBackgroundTask()
        defer {
            uploading.remove(ride.id)
            if uploading.isEmpty { endBackgroundTask() }
        }
        do {
            let file = store.tcxURL(for: ride)
            let request = Intervals.uploadRequest(file: try Data(contentsOf: file), filename: file.lastPathComponent,
                                                  name: "Raggio ride", externalID: ride.id.uuidString, apiKey: apiKey)
            DebugLog.shared.log(.intervals, "uploading ride \(ride.id.uuidString.prefix(8)), \(request.httpBody?.count ?? 0) bytes")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let outcome = try Intervals.outcome(status: status, body: data)
            DebugLog.shared.log(.intervals, "HTTP \(status): \(outcome)")
            record(.uploaded(activityID: outcome.activityID, at: Date()), for: ride)
        } catch {
            DebugLog.shared.log(.intervals, "upload failed: \(error.localizedDescription)")
            record(.failed(error.localizedDescription), for: ride)
        }
    }

    @MainActor
    private func record(_ state: Intervals.UploadState, for ride: Ride) {
        log.record(state, for: ride.id)
        save()
    }

    private func save() {
        try? JSONEncoder().encode(log).write(to: logFile, options: .atomic)
    }

    /// Lets an upload started just before the phone is locked finish.
    @MainActor
    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Intervals.icu upload") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    @MainActor
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
