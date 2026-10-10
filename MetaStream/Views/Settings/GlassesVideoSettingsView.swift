import SwiftUI

struct GlassesVideoSettingsView: View {
    @AppStorage("resolution") var resolution = "high"
    @AppStorage("fps") var fps = 30

    var body: some View {
        Form {
            Section {
                Picker("Resolution", selection: $resolution) {
                    Text("Low · 360×640").tag("low"); Text("Medium · 504×896").tag("medium"); Text("High · 720×1280").tag("high")
                }
                Picker("Frame rate", selection: $fps) { Text("15").tag(15); Text("24").tag(24); Text("30").tag(30) }
            } footer: {
                Text("Applied the next time the glasses session starts. 720×1280 at 30 fps is the ceiling — Meta's SDK offers third-party apps nothing higher, so no setting here can raise it.")
            }
        }
        .navigationTitle("Video (glasses)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
