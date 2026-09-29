import SwiftUI

@main
struct BikeComputerApp: App {
    @State private var recorder = RideRecorder(
        power: PowerMeterService(),
        workout: WorkoutSessionService(),
        location: LocationService(),
        store: RideStore())
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        DebugLog.shared.log(.app, "launch: Bike Computer \(version) (\(build)), "
            + "\(Self.deviceModel), iOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    /// Hardware identifier such as "iPhone17,1".
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(recorder)
        }
        .onChange(of: scenePhase) { _, phase in
            DebugLog.shared.log(.app, "scene \(phase)")
            // GPS runs in the background only while a ride is in progress.
            if phase == .background && recorder.state == .idle {
                recorder.location.stop()
            } else if phase == .active {
                recorder.location.start()
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Ride", systemImage: "bicycle") { RideView() }
            Tab("History", systemImage: "list.bullet") { HistoryView() }
            Tab("Settings", systemImage: "gear") { SettingsView() }
        }
    }
}
