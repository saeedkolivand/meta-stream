import SwiftUI
import UniformTypeIdentifiers

/// Everything about scenes that isn't one scene: the change transition, scene roles, auto-rotate, GPS share, OBS import.
/// Reached from Settings (Transitions) and from the Scenes screen's options button.
struct SceneOptionsView: View {
    @EnvironmentObject var streamer: Streamer
    @ObservedObject private var store = OverlayStore.shared
    @State private var pickJSON = false
    @State private var pickFolder = false
    @AppStorage("gpsShare") private var shareGPS = false
    @AppStorage("startCountdown") private var startCountdown = 60
    @AppStorage("endingHold") private var endingHold = 10

    var body: some View {
        Form {
            transitionSection
            Section {
                Stepper("Starting countdown: \(startCountdown == 0 ? "off" : "\(startCountdown) s")",
                        value: $startCountdown, in: 0...300, step: 5)
                Stepper("Ending hold: \(endingHold == 0 ? "off" : "\(endingHold) s")",
                        value: $endingHold, in: 0...60)
            } header: { Text("Scene roles") } footer: {
                Text("Give a scene a role in its editor. Starting shows after going live for the countdown "
                     + "(use {countdown} in a text widget), "
                     + "BRB while the connection is too weak, Ending for the hold after you tap END (tap again to stop at once). "
                     + "Picking a scene by hand cancels the role.")
            }
            rotateSection
            if UIDevice.current.userInterfaceIdiom == .phone {
                Section {
                    Toggle("Share GPS with iPad", isOn: $shareGPS)
                } footer: {
                    Text("For a Wi-Fi-only iPad on this iPhone's Personal Hotspot: it has no GPS, so its speed and distance "
                         + "come from here. Keeps location on in the background while on; anyone on your hotspot can read it.")
                }
                .onChange(of: shareGPS) { GPSShare.shared.setEnabled(shareGPS) }
            }
            importSection
        }
        .navigationTitle("Transitions & scene options")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: store.rotateOn) { streamer.updateSceneRotation() }
        .onChange(of: store.rotateSeconds) { streamer.updateSceneRotation() }
        .onChange(of: store.rotateScenes) { streamer.updateSceneRotation() }
    }

    private var transitionSection: some View {
        Section {
            Picker("Between scenes", selection: $store.transition) {
                Text("Cut").tag("cut")
                Text("Fade").tag("fade")
                Text("Stinger").tag("stinger")
            }
            .pickerStyle(.segmented)
            if store.transition == "stinger" {
                NavigationLink {
                    StingerSettingsView()
                } label: {
                    LabeledContent("Stinger", value: StingerKind(rawValue: store.stingerKind)?.title ?? "Your video")
                }
            }
        } header: { Text("Transition") } footer: {
            Text("Fade dims the old widgets out and the new ones in. A stinger plays over the change, which happens underneath it "
                 + "once the screen is covered. The camera itself switches instantly.")
        }
    }

    // MARK: rotation

    @ViewBuilder private var rotateSection: some View {
        Section {
            Toggle("Rotate scenes automatically", isOn: $store.rotateOn)
            if store.rotateOn {
                Picker("Every", selection: $store.rotateSeconds) {
                    ForEach([15, 30, 60, 120, 300], id: \.self) { Text($0 < 60 ? "\($0) seconds" : "\($0 / 60) min").tag($0) }
                }
                ForEach(store.scenes, id: \.name) { scene in
                    Button {
                        if let index = store.rotateScenes.firstIndex(of: scene.name) {
                            store.rotateScenes.remove(at: index)
                        } else {
                            store.rotateScenes.append(scene.name)
                        }
                    } label: {
                        HStack {
                            Text(scene.name).foregroundStyle(.primary)
                            Spacer()
                            if store.rotateScenes.contains(scene.name) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
            }
        } header: { Text("Auto-rotate") } footer: {
            Text(store.rotateOn ? "Pick at least two scenes. Picking a scene by hand that isn't in the list turns rotation off."
                 : "Cycles through the scenes you pick while you stream.")
        }
    }

    // MARK: OBS import

    private var importSection: some View {
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
        } header: { Text("Import from OBS (optional)") } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("In OBS: Scene Collection > Export, then pick that .json here. Imported scenes are added next to yours. "
                     + "Images, text, colors, slideshows, local clips and web pages come across; cameras, game and screen captures "
                     + "and audio are PC-only and skipped.")
                Text("Locate files takes the folder that holds the images and clips (iCloud Drive works) and copies the ones "
                     + "the scenes use into the app.")
                Text("The import holds your overlay page links, which can carry account tokens. It stays on this device, "
                     + "out of backups, and the links are never written to the log.")
                if let skipped = store.pack?.skippedText, !skipped.isEmpty { Text(skipped) }
            }
        }
    }
}
