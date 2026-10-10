import SwiftUI

struct DiagnosticsSettingsView: View {
    @EnvironmentObject var streamer: Streamer
    @AppStorage("keepAwake") var keepAwake = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Keep screen awake", isOn: $keepAwake)
            }
            Section("Logs") {
                NavigationLink("View logs") { LogView() }
            }
            Section("About") {
                row("Apple Team ID", streamer.teamID)
                row("Meta registration", streamer.registration)
                row("Devices", streamer.devices)
                row("Version", (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                    + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")")
            }
        }
        .navigationTitle("Diagnostics & about")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.footnote.monospaced()).textSelection(.enabled)
        }
    }
}
