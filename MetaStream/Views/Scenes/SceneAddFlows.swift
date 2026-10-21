import PhotosUI
import SwiftUI

/// The editor's add-widget flow: the gallery sheet, then whatever the pick needs (photo picker for an image, a link alert
/// for a web widget). The flow starts once the gallery has dismissed, so two presentations never overlap.
struct SceneAddFlows: ViewModifier {
    @Binding var showGallery: Bool
    /// Receives the finished layer (the editor appends, selects and saves it).
    let add: (OverlayLayer) -> Void
    @State private var pending: NewWidget?
    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var showWeb = false
    @State private var webURL = ""
    @State private var webNote = ""

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showGallery, onDismiss: startPending) {
                AddWidgetGallery { pending = $0 }.presentationDetents([.medium, .large])
            }
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
    }

    private func startPending() {
        guard let kind = pending else { return }
        pending = nil
        switch kind {
        case .image: showPhotos = true
        case .web: webNote = ""; webURL = ""; showWeb = true
        default: if let layer = kind.make() { add(layer) }
        }
    }

    private func addImage(_ data: Data) {
        guard let file = OverlayStore.shared.saveImage(data) else { return }
        add(.pickedImage(file: file))
    }

    private func addWeb() {
        let trimmed = webURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let link = URL(string: trimmed), ["http", "https"].contains(link.scheme?.lowercased()), link.host != nil else {
            webNote = "That isn't an http or https link. "
            Task { showWeb = true }   // next turn: the alert is still dismissing while its button runs
            return
        }
        add(.web(url: trimmed))
    }
}
