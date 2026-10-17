import SwiftUI

struct RemoteSettingsView: View {
    @EnvironmentObject var streamer: Streamer
    @AppStorage("obsServerOn") var on = false
    @AppStorage("obsPassword") var password = ""

    var body: some View {
        Form {
            Section {
                Toggle("obs-websocket server", isOn: $on)
            } footer: {
                Text("Lets Stream Deck, Touch Portal and Streamer.bot control the app as if it were OBS: scenes, go live, record, mic, sounds. Local network only (same Wi-Fi, or this device's hotspot). In the controller, add an OBS connection with the address, port and password below.")
            }
            if on {
                Section("Password") {
                    TextField("Password", text: $password).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Regenerate") { password = ObsServer.randomPassword() }
                }
                Section("Address (port \(String(ObsServer.port)))") {
                    let ips = ObsServer.addresses()
                    ForEach(ips, id: \.1) { LabeledContent($0.0, value: $0.1) }
                    if ips.isEmpty { Text("Not on a network").foregroundStyle(.secondary) }
                }
            }
        }
        .onChange(of: on) { _, _ in ObsServer.shared.sync(streamer) }
        .navigationTitle("Remote control")
        .navigationBarTitleDisplayMode(.inline)
    }
}
