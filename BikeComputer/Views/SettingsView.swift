import SwiftUI

struct SettingsView: View {
    @Environment(RideRecorder.self) private var recorder
    @AppStorage("useMetric") private var useMetric = false
    @AppStorage(IntervalsSync.autoUploadKey) private var autoUpload = true
    @State private var apiKey = Keychain.read(Keychain.intervalsAPIKey) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Metric units", isOn: $useMetric)
                Section {
                    SecureField("API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveKey)
                    Button("Save key", action: saveKey)
                    Toggle("Upload rides automatically", isOn: $autoUpload)
                } header: {
                    Text("Intervals.icu")
                } footer: {
                    Text("Key: Intervals.icu → Settings → Developer Settings. Stored in the iOS Keychain on this phone only. Each saved ride uploads by itself (retried when you next open the app if there's no signal), and remymargerum.com/cycling picks it up on its hourly sync.")
                }
                Section {
                    NavigationLink("Debug log") { DebugLogView() }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Raw power-meter packets, heart rate, GPS accuracy and sensor events. No map coordinates. Share it when something doesn't work.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func saveKey() {
        Keychain.write(apiKey, for: Keychain.intervalsAPIKey)
        // Rides that failed for lack of a key can go now.
        Task { await recorder.intervals.sync() }
    }
}
