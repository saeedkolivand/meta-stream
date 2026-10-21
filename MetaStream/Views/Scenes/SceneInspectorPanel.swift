import SwiftUI

/// The inspector chrome: the layer's name, a Content | Style | Position switch, and that tab's form. The iPhone sheet
/// passes `close`; the iPad pane doesn't need it.
struct SceneInspectorPanel: View {
    @Binding var layer: OverlayLayer
    let canMoveForward: Bool
    let canMoveBack: Bool
    let commit: () -> Void
    let move: (Int) -> Void
    let delete: () -> Void
    var close: (() -> Void)?
    @State private var tab = InspectorTab.content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: layer.type.icon).foregroundStyle(.tint)
                Text(layer.name).font(.headline).lineLimit(1)
                Spacer()
                if let close { Button("Done", action: close).frame(minHeight: 44) }
            }
            .padding(.horizontal, 16)
            Picker("Section", selection: $tab) {
                ForEach(InspectorTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            Form {
                WidgetInspectorView(layer: $layer, tab: tab, canMoveForward: canMoveForward, canMoveBack: canMoveBack,
                                    commit: commit, move: move, delete: delete)
            }
        }
    }
}

/// Floating toolbar over the selected widget: edit, duplicate, bring forward, hide, delete.
struct SceneSelectionBar: View {
    /// nil on iPad, where the inspector is always on screen.
    let edit: (() -> Void)?
    let duplicate: () -> Void
    let forward: () -> Void
    let hide: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if let edit { item("Edit widget", "slider.horizontal.3", edit) }
            item("Duplicate widget", "plus.square.on.square", duplicate)
            item("Bring forward", "square.2.layers.3d.top.filled", forward)
            item("Hide widget", "eye.slash", hide)
            item("Delete widget", "trash", delete, tint: .red)
        }
        .padding(2)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
    }

    private func item(_ label: String, _ icon: String, _ action: @escaping () -> Void, tint: Color = .primary) -> some View {
        Button(action: action) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }
}
