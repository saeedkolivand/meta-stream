import SwiftUI

/// Meta glasses on/off plus their video settings. Off (the default) hides every glasses control on the main screen.
struct GlassesVideoSettingsView: View {
    @EnvironmentObject var streamer: Streamer
    @AppStorage("glassesEnabled") var glassesEnabled = false
    @AppStorage("resolution") var resolution = "high"
    @AppStorage("fps") var fps = 30

    var body: some View {
        Form {
            Section {
                Toggle("Use Meta glasses", isOn: $glassesEnabled)
            } footer: {
                Text("Shows the glasses button, the Glasses and Auto sources and the glasses status pill on the main screen. Auto streams from the glasses and falls back to the phone camera when they drop.")
            }
            if glassesEnabled {
                Section {
                    Picker("Resolution", selection: $resolution) {
                        Text("Low · 360×640").tag("low"); Text("Medium · 504×896").tag("medium"); Text("High · 720×1280").tag("high")
                    }
                    Picker("Frame rate", selection: $fps) { Text("15").tag(15); Text("24").tag(24); Text("30").tag(30) }
                } header: { Text("Video") } footer: {
                    Text("Applied the next time the glasses session starts. 720×1280 at 30 fps is the ceiling — Meta's SDK offers third-party apps nothing higher, so no setting here can raise it.")
                }
            }
        }
        .onChange(of: glassesEnabled) { _, on in
            guard !on else { return }
            if streamer.glassesOn { streamer.stopGlasses() }
            if streamer.manualSource == "glasses" || streamer.manualSource == "auto" { streamer.setSource("back") }
        }
        .navigationTitle("Meta glasses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
