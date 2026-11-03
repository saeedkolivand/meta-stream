import SwiftUI

struct PrivacySettingsView: View {
    @AppStorage("blurOn") var blurOn = false
    @AppStorage("blurFaces") var blurFaces = true
    @AppStorage("blurText") var blurText = true
    @AppStorage("blurBarcodes") var blurBarcodes = true

    var body: some View {
        Form {
            Section {
                Toggle("Privacy blur", isOn: $blurOn)
                if blurOn {
                    Toggle("Faces", isOn: $blurFaces)
                    Toggle("Text and licence plates", isOn: $blurText)
                    Toggle("QR codes and barcodes", isOn: $blurBarcodes)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pixellates faces, text and codes in the outgoing video. Licence plates come from the text detector, since a plate is text.")
                    Text("This is best effort, not a guarantee. Detection runs per frame and misses profile faces, motion blur, distance and low light, so some frames go out unobscured and there is no undo on a live stream. It reduces what gets seen; it is not a substitute for not pointing the camera at something.")
                    Text("Turning it on forces a transcode on every destination, because a frame has to be decoded to be altered. That costs battery and heat, and background streaming will need the Picture in Picture window. If detection stops working the camera is hidden and you are told, rather than the stream quietly going clear.")
                }
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
