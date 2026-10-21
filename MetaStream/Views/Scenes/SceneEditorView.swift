import SwiftUI

/// Build one scene: arrange widgets on a live canvas, pick the camera it switches to, put it on stream.
/// iPhone: canvas on top, a bottom bar (layers, add, camera), the inspector in a sheet that leaves the canvas usable.
/// iPad: layers | canvas | inspector side by side. State and actions are internal so SceneEditorActions.swift can extend it.
struct SceneEditorView: View {
    @EnvironmentObject var streamer: Streamer
    @ObservedObject var store = OverlayStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    // Emotes is owned by ContentView and isn't an environment object; samples render fine without emote images.
    @StateObject private var emotes = Emotes()
    @State var name: String
    @State var draftName: String
    @State var layers: [OverlayLayer] = []
    @State var selected: Int?
    @State var saveTask: Task<Void, Never>?
    @State var showGallery = false
    @State private var portraitOverride: Bool?
    @State private var showLayers = false
    @State private var showInspector = false
    @State private var renaming = false
    /// Canvas only: the bottom bar, layers and inspector step aside (the floating selection bar stays).
    @State private var fullScreen = false

    init(name: String) {
        _name = State(initialValue: name)
        _draftName = State(initialValue: name)
    }

    private var canvas: CGSize {
        let b = streamer.blurCanvasSize
        let lo = min(b.width, b.height), hi = max(b.width, b.height)
        let (s, l) = lo > 0 ? (lo, hi) : (1080, 1920)
        return portrait ? CGSize(width: s, height: l) : CGSize(width: l, height: s)
    }

    private var portrait: Bool { portraitOverride ?? (streamer.blurCanvasSize.height > streamer.blurCanvasSize.width) }
    private var regular: Bool { sizeClass == .regular }
    var stored: [OverlayLayer] { store.scenes.first { $0.name == name }?.layers ?? [] }
    private var wantsLocation: Bool { layers.contains { $0.type == .text && WidgetVariables.needsLocation($0.data["text"] ?? "") } }
    private var camera: String { store.scenes.first { $0.name == name }?.camera ?? "" }
    private var role: String { store.scenes.first { $0.name == name }?.role ?? "" }
    /// On stream right now: edits wait as a draft until applied, so viewers never see a half-built scene.
    var liveLocked: Bool { streamer.live && store.scene == name }

    var body: some View {
        Group {
            if regular { padLayout } else { phoneLayout }
        }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .modifier(SceneAddFlows(showGallery: $showGallery, add: append))
            .sheet(isPresented: $showLayers) { layersSheet }
            .sheet(isPresented: $showInspector) { inspectorSheet }
            .alert("Rename scene", isPresented: $renaming) {
                TextField("Name", text: $draftName)
                Button("Rename", action: renameIfNeeded)
                Button("Cancel", role: .cancel) { draftName = name }
            } message: {
                Text("Names must be unique.")
            }
            .onAppear { layers = stored }
            .task(id: wantsLocation) {
                // The editor preview resolves {speed}/{weather} itself, so it keeps GPS on while it shows them.
                guard wantsLocation else { return }
                WidgetLocation.shared.retain()
                while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
                WidgetLocation.shared.release()
            }
            .onChange(of: layers) { scheduleSave() }
            .onChange(of: selected) { if selected == nil { showInspector = false } }
            .onDisappear { renameIfNeeded(); applyNow() }   // leaving is done: an unapplied live draft goes out too
    }

    // MARK: layouts

    private var phoneLayout: some View {
        VStack(spacing: 0) {
            draftBanner
            canvasView.padding(.horizontal, fullScreen ? 4 : 16).padding(.top, fullScreen ? 0 : 16).padding(.bottom, fullScreen ? 0 : 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !fullScreen { bottomBar }
        }
    }

    private var padLayout: some View {
        VStack(spacing: 0) {
            draftBanner
            HStack(spacing: 0) {
                if !fullScreen {
                    layersPane
                    Divider()
                }
                canvasView.padding(fullScreen ? 4 : 16).frame(maxWidth: .infinity, maxHeight: .infinity)
                if !fullScreen {
                    Divider()
                    inspectorPane
                }
            }
        }
    }

    private var layersPane: some View {
        VStack(spacing: 8) {
            SceneLayerList(layers: $layers, selected: $selected, delete: remove, reorder: reorder)
            Button { showGallery = true } label: {
                Label("Add widget", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 250)
    }

    private var inspectorPane: some View {
        Group {
            if let idx = selected, layers.indices.contains(idx) {
                inspector(idx, close: nil)
            } else {
                Text("Select a widget to edit it.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 300)
    }

    private var canvasView: some View {
        SceneCanvasView(layers: layers, canvas: canvas, selected: $selected, emotes: emotes) { idx, layer in
            guard layers.indices.contains(idx) else { return }
            layers[idx] = layer
            saveNow()
        }
        .selectionBar {
            SceneSelectionBar(edit: regular ? nil : { showInspector = true }, duplicate: onSelected(duplicate),
                              forward: onSelected { move($0, 1) }, hide: onSelected(hide), delete: onSelected(remove))
        }
        .frame(maxWidth: .infinity)
    }

    /// An action on whichever widget is selected when it runs (the canvas toolbar outlives selection changes).
    private func onSelected(_ action: @escaping (Int) -> Void) -> () -> Void {
        { if let idx = selected { action(idx) } }
    }

    private var bottomBar: some View {
        HStack {
            Button { showLayers = true } label: {
                VStack(spacing: 2) {
                    Image(systemName: "square.3.layers.3d")
                    Text("Layers").font(.caption2)
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .frame(maxWidth: .infinity)
            Button { hapticTap(); showGallery = true } label: {
                Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(Color.accentColor, in: Circle())
            }
            .accessibilityLabel("Add widget")
            .frame(maxWidth: .infinity)
            Menu {
                Picker("Camera", selection: cameraBinding) { ForEach(cameraOptions, id: \.0) { Text($0.1).tag($0.0) } }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: sceneCameraIcon(camera))
                    Text(sceneCameraTitle(camera) ?? "Camera").font(.caption2).lineLimit(1)
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Camera")
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: chrome

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Menu {
                Button { draftName = name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                Menu("Camera") { Picker("Camera", selection: cameraBinding) { ForEach(cameraOptions, id: \.0) { Text($0.1).tag($0.0) } } }
                Menu("Role") {
                    Picker("Role", selection: roleBinding) {
                        Text("None").tag("")
                        Text("Starting").tag("starting")
                        Text("BRB").tag("brb")
                        Text("Ending").tag("ending")
                    }
                }
                Toggle("Show on stream", isOn: Binding(get: { store.scene == name }, set: { streamer.selectScene($0 ? name : "") }))
            } label: {
                HStack(spacing: 4) {
                    Text(name).font(.headline)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Scene options for \(name)")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                fullScreen.toggle()
                if fullScreen { showLayers = false; showInspector = false }
            } label: {
                Image(systemName: fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityLabel(fullScreen ? "Exit full screen editing" : "Full screen editing")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { portraitOverride = !portrait } label: { Image(systemName: portrait ? "rectangle.portrait" : "rectangle") }
                .accessibilityLabel(portrait ? "Preview in landscape" : "Preview in portrait")
        }
    }

    @ViewBuilder private var draftBanner: some View {
        if liveLocked, layers != stored {
            let count = max(1, zip(layers, stored).filter { $0 != $1 }.count + abs(layers.count - stored.count))
            HStack {
                Text(count == 1 ? "1 change waits until you apply it" : "\(count) changes wait until you apply them").font(.footnote)
                Spacer()
                Button("Discard", role: .destructive) { selected = nil; layers = stored }.frame(minHeight: 44)
                Button("Apply") { hapticTap(); applyNow() }.buttonStyle(.borderedProminent).frame(minHeight: 44)
            }
            .padding(.horizontal, 16)
            .background(Color.orange.opacity(0.18))
        }
    }

    // MARK: sheets

    private var layersSheet: some View {
        SceneLayerList(layers: $layers, selected: Binding(get: { selected }, set: { selected = $0; showLayers = false }),
                       delete: remove, reorder: reorder)
            .padding(.top, 16)
            .presentationDetents([.medium, .large])
    }

    private var inspectorSheet: some View {
        Group {
            if let idx = selected, layers.indices.contains(idx) { inspector(idx, close: { showInspector = false }) }
        }
        .padding(.top, 16)
        .presentationDetents([.fraction(0.45), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
        .presentationDragIndicator(.visible)
    }

    private func inspector(_ idx: Int, close: (() -> Void)?) -> some View {
        SceneInspectorPanel(layer: $layers[idx], canMoveForward: idx < layers.count - 1, canMoveBack: idx > 0,
                            commit: saveNow, move: { move(idx, $0) }, delete: { remove(idx) }, close: close)
    }

    // MARK: camera and role

    private var cameraBinding: Binding<String> {
        Binding(get: { camera }, set: { store.setCamera($0.isEmpty ? nil : $0, in: name) })
    }

    private var roleBinding: Binding<String> {
        Binding(get: { role }, set: { store.setRole($0.isEmpty ? nil : $0, in: name) })
    }

    /// Always lists the scene's current camera, even when it isn't available right now, so the picker never goes blank.
    private var cameraOptions: [(String, String)] {
        var o = [("", "Keep current"), ("back", "Back camera"), ("front", "Front camera")]
        if streamer.externalCameraName != nil || camera == "external" { o.append(("external", streamer.externalCameraName ?? "External camera")) }
        if Streamer.glassesConfigured || camera == "glasses" { o.append(("glasses", "Glasses")) }
        if camera == "auto" { o.append(("auto", "Auto")) }
        return o
    }
}
