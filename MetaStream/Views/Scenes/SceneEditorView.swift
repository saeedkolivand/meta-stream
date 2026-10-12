import PhotosUI
import SwiftUI

/// Build one scene: arrange widgets on a live canvas, pick the camera it switches to, put it on stream.
/// The canvas stays pinned while the form below scrolls, so every inspector change shows up immediately.
struct SceneEditorView: View {
    @EnvironmentObject private var streamer: Streamer
    @ObservedObject private var store = OverlayStore.shared
    // Emotes is owned by ContentView and isn't an environment object; samples render fine without emote images.
    @StateObject private var emotes = Emotes()
    @State private var name: String
    @State private var draftName: String
    @State private var layers: [OverlayLayer] = []
    @State private var selected: Int?
    @State private var portraitOverride: Bool?
    @State private var saveTask: Task<Void, Never>?
    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var showWeb = false
    @State private var webURL = ""
    @State private var webNote = ""

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
    private var stored: [OverlayLayer] { store.scenes.first { $0.name == name }?.layers ?? [] }
    private var camera: String { store.scenes.first { $0.name == name }?.camera ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Picker("Preview", selection: Binding(get: { portrait }, set: { portraitOverride = $0 })) {
                    Text("Landscape").tag(false)
                    Text("Portrait").tag(true)
                }
                .pickerStyle(.segmented)
                SceneCanvasView(layers: layers, canvas: canvas, selected: $selected, emotes: emotes) { i, l in
                    guard layers.indices.contains(i) else { return }
                    layers[i] = l
                    saveNow()
                }
                .frame(maxHeight: 300)
                .frame(maxWidth: .infinity)
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 8)
            form
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { AddWidgetMenu(pick: add) } }
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { addImage(data) }
                photo = nil
            }
        }
        .alert("Web widget", isPresented: $showWeb) {
            TextField("https://", text: $webURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Add", action: addWeb)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(webNote + "Paste a Streamlabs, StreamElements or BotRix widget link for alerts, goals or anything web-based.")
        }
        .onAppear { layers = stored }
        .onChange(of: layers) { scheduleSave() }
        .onDisappear { renameIfNeeded(); saveNow() }
    }

    // MARK: form

    private var form: some View {
        Form {
            Section {
                TextField("Name", text: $draftName).onSubmit(renameIfNeeded)
                Toggle("Show on stream", isOn: Binding(
                    get: { store.scene == name },
                    set: { streamer.selectScene($0 ? name : "") }))
                Picker("Camera", selection: Binding(get: { camera }, set: { store.setCamera($0.isEmpty ? nil : $0, in: name) })) {
                    ForEach(cameraOptions, id: \.0) { Text($0.1).tag($0.0) }
                }
            } footer: {
                Text("Switching to this scene also switches the camera, so one tap can go from the glasses to the back camera.")
            }
            Section("Layers") {
                if layers.isEmpty {
                    Text("Nothing here yet. Tap + to add chat, alerts, text, an image and more.").foregroundStyle(.secondary)
                }
                ForEach(Array(layers.indices.reversed()), id: \.self) { i in layerRow(i) }
            }
            if let i = selected, layers.indices.contains(i) {
                WidgetInspectorView(layer: $layers[i], canMoveForward: i < layers.count - 1, canMoveBack: i > 0,
                                    commit: saveNow, move: { move(i, $0) }, delete: { remove(i) })
            }
        }
    }

    private func layerRow(_ i: Int) -> some View {
        HStack {
            Button { selected = i } label: {
                HStack {
                    Image(systemName: layers[i].type.icon).frame(width: 26).foregroundStyle(.tint)
                    Text(layers[i].name).foregroundStyle(layers[i].visible ? .primary : .secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            Button { layers[i].visible.toggle() } label: {
                Image(systemName: layers[i].visible ? "eye" : "eye.slash")
            }
            .accessibilityLabel(layers[i].visible ? "Hide \(layers[i].name)" : "Show \(layers[i].name)")
        }
        .buttonStyle(.borderless)
        .listRowBackground(selected == i ? Color.accentColor.opacity(0.2) : Color(.secondarySystemGroupedBackground))
        .swipeActions {
            Button(role: .destructive) { remove(i) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// Always lists the scene's current camera, even when it isn't available right now, so the picker never goes blank.
    private var cameraOptions: [(String, String)] {
        var o = [("", "Keep current"), ("back", "Back camera"), ("front", "Front camera")]
        if streamer.externalCameraName != nil || camera == "external" { o.append(("external", streamer.externalCameraName ?? "External camera")) }
        if Streamer.glassesConfigured || camera == "glasses" { o.append(("glasses", "Glasses")) }
        if camera == "auto" { o.append(("auto", "Auto")) }
        return o
    }

    // MARK: edits

    private func add(_ kind: NewWidget) {
        switch kind {
        case .image: showPhotos = true
        case .web: webNote = ""; webURL = ""; showWeb = true
        default: if let l = kind.make() { append(l) }
        }
    }

    private func append(_ l: OverlayLayer) {
        layers.append(l)
        selected = layers.count - 1
        hapticTap()
        saveNow()
    }

    private func addImage(_ data: Data) {
        guard let file = store.saveImage(data) else { return }
        append(.pickedImage(file: file))
    }

    private func addWeb() {
        let s = webURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: s), ["http", "https"].contains(u.scheme?.lowercased()), u.host != nil else {
            webNote = "That isn't an http or https link. "
            Task { showWeb = true }   // next turn: the alert is still dismissing while its button runs
            return
        }
        append(.web(url: s))
    }

    private func remove(_ i: Int) {
        guard layers.indices.contains(i) else { return }
        layers.remove(at: i)
        selected = nil
        hapticTap()
        saveNow()
    }

    private func move(_ i: Int, _ by: Int) {
        let j = i + by
        guard layers.indices.contains(i), layers.indices.contains(j) else { return }
        layers.swapAt(i, j)
        selected = j
        saveNow()
    }

    private func renameIfNeeded() {
        let t = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != name else { draftName = name; return }
        if store.renameScene(name, to: t) { name = t; draftName = t } else { draftName = name }
    }

    /// Debounced: sliders, colour pickers and typing change the layers many times a second, and every save rebuilds
    /// the scene on stream.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { saveNow() }
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        if layers != stored { store.setLayers(layers, in: name) }
    }
}
