import SwiftUI
import UniformTypeIdentifiers

/// Import an OBS scene collection, find its files, pick the scene drawn on the stream.
struct OverlaySettingsView: View {
    @EnvironmentObject var streamer: Streamer
    @ObservedObject private var store = OverlayStore.shared
    @State private var pickJSON = false
    @State private var pickFolder = false

    var body: some View {
        Form {
            Section {
                Button("Import OBS scene collection") { pickJSON = true }
                    .fileImporter(isPresented: $pickJSON, allowedContentTypes: [.json, .data]) { result in
                        if case .success(let url) = result { Task { await store.importPack(from: url) } }
                    }
                if !store.missing.isEmpty {
                    Button("Locate files…") { pickFolder = true }
                        .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder]) { result in
                            if case .success(let url) = result { Task { await store.locate(in: url) } }
                        }
                }
                if store.busy { ProgressView() }
                if !store.message.isEmpty {
                    Text(store.message).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In OBS: Scene Collection > Export, then pick that .json here. Images, text, colors, slideshows, local clips and web pages come across; cameras, game and screen captures and audio are PC-only and skipped.")
                    Text("Locate files takes the folder that holds the images and clips (iCloud Drive works) and copies the ones the scenes use into the app.")
                    Text("The import holds your overlay page links, which can carry account tokens. It stays on this device, out of backups, and the links are never written to the log.")
                }
            }
            if let pack = store.pack {
                Section {
                    if !streamer.overlaysUsable {
                        Text("Overlays are off for glasses HEVC passthrough. Use the phone camera, or the H.264 codec.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    sceneRow("", "None")
                    ForEach(Array(pack.scenes.enumerated()), id: \.offset) { _, scene in sceneRow(scene.name, scene.name) }
                } header: {
                    Text("Scene")
                } footer: {
                    Text(pack.skippedText)
                }
            }
        }
        .navigationTitle("Overlays")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sceneRow(_ name: String, _ label: String) -> some View {
        Button {
            store.select(name)
        } label: {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                if store.scene == name { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
