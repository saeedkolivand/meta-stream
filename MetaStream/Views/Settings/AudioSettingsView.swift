import SwiftUI

struct AudioSettingsView: View {
    @EnvironmentObject var streamer: Streamer
    @AppStorage("micUID") var micUID = ""

    var body: some View {
        Form {
            Section {
                Picker("Microphone", selection: $micUID) {
                    Text("Default").tag("")
                    ForEach(streamer.mics) { Text($0.name).tag($0.id) }
                }
                Toggle("Mute microphone", isOn: Binding(get: { streamer.muted }, set: { streamer.setMuted($0) }))
            }
        }
        .navigationTitle("Audio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { streamer.refreshMics() }
    }
}
