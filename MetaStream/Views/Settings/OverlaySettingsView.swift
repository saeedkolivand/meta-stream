import SwiftUI

/// The Scenes screen: a grid of scene cards (thumbnail, role, on-stream badge). Tap one to arrange its widgets, hold for
/// show / duplicate / rename / delete. Transitions, roles, rotation and OBS import live behind the options button.
struct OverlaySettingsView: View {
    @EnvironmentObject var streamer: Streamer
    @EnvironmentObject var platforms: Platforms
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var store = OverlayStore.shared
    @State private var editing: String?
    @State private var renaming: String?
    @State private var renameText = ""

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 230 : 150), spacing: 14, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !streamer.overlaysUsable {
                    Text("Overlays are off for glasses HEVC passthrough. Use the phone camera, or the H.264 codec.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                noneRow
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(store.scenes, id: \.name) { card($0) }
                }
                if store.scenes.isEmpty {
                    Text("No scenes yet. Tap + to make one, or add the Starting, BRB & Ending set.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("Tap a scene to arrange its widgets. Hold one to show it on stream, duplicate, rename or delete it. "
                     + "The Starting, BRB & Ending set takes those roles over from your other scenes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("Scenes & widgets")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editing) { SceneEditorView(name: $0) }
        .toolbar { toolbar }
        .alert("Rename scene", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let old = renaming { _ = store.renameScene(old, to: renameText.trimmingCharacters(in: .whitespaces)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Names must be unique.")
        }
    }

    // MARK: pieces

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink {
                SceneOptionsView()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Transitions and scene options")
            Menu {
                Button { hapticTap(); editing = store.addScene() } label: { Label("New scene", systemImage: "plus.rectangle") }
                Menu {
                    ForEach(SceneTemplate.allCases, id: \.self) { template in
                        Button(template.rawValue) { hapticTap(); store.addTemplate(template, channel: platforms.kickUser) }
                    }
                } label: {
                    Label("Add Starting, BRB & Ending scenes", systemImage: "rectangle.stack.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add scene")
        }
    }

    private var noneRow: some View {
        Button {
            hapticTap()
            streamer.selectScene("")
        } label: {
            HStack {
                Text("None (no overlay)").foregroundStyle(.primary)
                Spacer()
                if store.scene.isEmpty { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .padding(14)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func card(_ scene: OverlayScene) -> some View {
        Button { editing = scene.name } label: {
            SceneCard(scene: scene, onStream: store.scene == scene.name)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { streamer.selectScene(scene.name) } label: { Label("Show on stream", systemImage: "play.rectangle") }
            Button { _ = store.duplicateScene(scene.name) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { renameText = scene.name; renaming = scene.name } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) {
                hapticTap()
                store.deleteScene(scene.name)
                streamer.updateSceneRotation()
            } label: { Label("Delete", systemImage: "trash") }
        }
    }
}
