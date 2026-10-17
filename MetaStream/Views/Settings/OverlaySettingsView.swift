import SwiftUI
import UniformTypeIdentifiers

/// Scenes you build in the app (widgets, camera per scene, auto-rotate), plus the optional OBS import.
struct OverlaySettingsView: View {
    @EnvironmentObject var streamer: Streamer
    @EnvironmentObject var platforms: Platforms
    @ObservedObject private var store = OverlayStore.shared
    @State private var editing: String?
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var pickJSON = false
    @State private var pickFolder = false
    @AppStorage("gpsShare") private var shareGPS = false
    @AppStorage("startCountdown") private var startCountdown = 60
    @AppStorage("endingHold") private var endingHold = 10

    var body: some View {
        Form {
            scenesSection
            rotateSection
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
                Text("Fade dims the old widgets out and the new ones in. A stinger plays over the change, which happens underneath it once the screen is covered. The camera itself switches instantly.")
            }
            Section {
                Stepper("Starting countdown: \(startCountdown == 0 ? "off" : "\(startCountdown) s")", value: $startCountdown, in: 0...300, step: 5)
                Stepper("Ending hold: \(endingHold == 0 ? "off" : "\(endingHold) s")", value: $endingHold, in: 0...60)
            } header: { Text("Scene roles") } footer: {
                Text("Give a scene a role in its editor. Starting shows after going live for the countdown (use {countdown} in a text widget), BRB while the connection is too weak, Ending for the hold after you tap END (tap again to stop at once). Picking a scene by hand cancels the role.")
            }
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
        .navigationTitle("Scenes & widgets")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editing) { SceneEditorView(name: $0) }
        .onChange(of: store.rotateOn) { streamer.updateSceneRotation() }
        .onChange(of: store.rotateSeconds) { streamer.updateSceneRotation() }
        .onChange(of: store.rotateScenes) { streamer.updateSceneRotation() }
        .alert("Rename scene", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let old = renaming { _ = store.renameScene(old, to: renameText.trimmingCharacters(in: .whitespaces)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Names must be unique.")
        }
    }

    // MARK: scenes

    private var scenesSection: some View {
        Section {
            if !streamer.overlaysUsable {
                Text("Overlays are off for glasses HEVC passthrough. Use the phone camera, or the H.264 codec.")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Button {
                hapticTap()
                streamer.selectScene("")
            } label: {
                HStack {
                    Text("None (no overlay)").foregroundStyle(.primary)
                    Spacer()
                    if store.scene.isEmpty { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
            ForEach(store.scenes, id: \.name) { sceneRow($0) }
            Button {
                hapticTap()
                editing = store.addScene()
            } label: {
                Label("New scene", systemImage: "plus.circle.fill")
            }
            Menu {
                ForEach(SceneTemplate.allCases, id: \.self) { t in
                    Button(t.rawValue) { hapticTap(); store.addTemplate(t, channel: platforms.kickUser) }
                }
            } label: {
                Label("Add Starting, BRB & Ending scenes", systemImage: "rectangle.stack.badge.plus")
            }
        } header: { Text("Scenes") } footer: {
            Text("Tap a scene to arrange its widgets. Hold one to show it on stream, duplicate or rename it. The Starting, BRB & Ending set takes those roles over from your other scenes.")
        }
    }

    private func sceneRow(_ scene: OverlayScene) -> some View {
        Button { editing = scene.name } label: {
            HStack(spacing: 8) {
                Text(scene.name).foregroundStyle(.primary)
                if let cam = scene.camera { Image(systemName: Self.cameraIcon(cam)).font(.footnote).foregroundStyle(.secondary) }
                Spacer()
                if store.scene == scene.name {
                    Text("ON STREAM").font(.caption2.weight(.bold)).foregroundStyle(.green)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.green.opacity(0.18), in: Capsule())
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .swipeActions {
            Button(role: .destructive) {
                hapticTap()
                store.deleteScene(scene.name)
                streamer.updateSceneRotation()
            } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Button { streamer.selectScene(scene.name) } label: { Label("Show on stream", systemImage: "play.rectangle") }
            Button { _ = store.duplicateScene(scene.name) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { renameText = scene.name; renaming = scene.name } label: { Label("Rename", systemImage: "pencil") }
        }
    }

    private static func cameraIcon(_ cam: String) -> String {
        switch cam {
        case "front": "person.crop.circle"
        case "external": "video.fill"
        case "glasses": "eyeglasses"
        default: "camera.fill"
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
                ForEach(store.scenes, id: \.name) { s in
                    Button {
                        if let i = store.rotateScenes.firstIndex(of: s.name) { store.rotateScenes.remove(at: i) } else { store.rotateScenes.append(s.name) }
                    } label: {
                        HStack {
                            Text(s.name).foregroundStyle(.primary)
                            Spacer()
                            if store.rotateScenes.contains(s.name) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
            }
        } header: { Text("Auto-rotate") } footer: {
            Text(store.rotateOn ? "Pick at least two scenes. Picking a scene by hand that isn't in the list turns rotation off." : "Cycles through the scenes you pick while you stream.")
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
                Text("In OBS: Scene Collection > Export, then pick that .json here. Imported scenes are added next to yours. Images, text, colors, slideshows, local clips and web pages come across; cameras, game and screen captures and audio are PC-only and skipped.")
                Text("Locate files takes the folder that holds the images and clips (iCloud Drive works) and copies the ones the scenes use into the app.")
                Text("The import holds your overlay page links, which can carry account tokens. It stays on this device, out of backups, and the links are never written to the log.")
                if let skipped = store.pack?.skippedText, !skipped.isEmpty { Text(skipped) }
            }
        }
    }
}
