import SwiftUI

struct SettingsView: View {
    @AppStorage("useMetric") private var useMetric = false
    @State private var apiKey = Keychain.read(Keychain.intervalsAPIKey) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Metric units", isOn: $useMetric)
                Section {
                    SecureField("API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Keychain.write(apiKey, for: Keychain.intervalsAPIKey) }
                    Button("Save key") { Keychain.write(apiKey, for: Keychain.intervalsAPIKey) }
                } header: {
                    Text("Intervals.icu")
                } footer: {
                    Text("Intervals.icu → Settings → Developer Settings. Stored in the iOS Keychain on this phone only.")
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
}
