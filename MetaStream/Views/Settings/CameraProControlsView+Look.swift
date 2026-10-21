import SwiftUI

extension CameraProControlsView {
    var lookSection: some View {
        Section {
            labeledSlider("Brightness", valueText: String(format: "%+.2f", look.brightness), value: $look.brightness, range: -0.5...0.5)
            labeledSlider("Contrast", valueText: String(format: "%.2f", look.contrast), value: $look.contrast, range: 0.5...1.5)
            labeledSlider("Saturation", valueText: String(format: "%.2f", look.saturation), value: $look.saturation, range: 0...2)
            labeledSlider("Warmth", valueText: String(format: "%+.2f", look.warmth), value: $look.warmth, range: -1...1)
            Picker("LUT", selection: $look.lut) {
                Text("None").tag(String?.none)
                ForEach(luts, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            Button("Import…") { importingLUT = true }
            ForEach(luts, id: \.self) { Text($0).foregroundStyle(.secondary) }
                .onDelete { offsets in
                    for idx in offsets {
                        try? FileManager.default.removeItem(at: Look.folder.appending(path: luts[idx]))
                        if look.lut == luts[idx] { look.lut = nil }
                    }
                    luts = Look.files()
                }
            if let lutError { Text(lutError).foregroundStyle(.orange) }
            if streamer.live, !streamer.transcoding, streamer.lookKey == "glasses", !look.isNeutral {
                Text("Applies from the next stream.").foregroundStyle(.orange)
            }
            Button("Reset", role: .destructive) { look = Look() }
                .disabled(look.isNeutral)
        } header: { Text("Look (\(streamer.lookKey))") } footer: {
            Text("A look changes the picture, so the glasses' video is re-encoded (H.264) while it's not neutral.")
        }
    }
}
