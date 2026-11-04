import SwiftUI

/// The inspector chrome: the layer's name, a Content | Style | Position switch, and that tab's form. The iPhone sheet
/// passes `close`; the iPad pane doesn't need it.
public struct SceneInspectorPanel: View {
    @Binding var layer: OverlayLayer
    public let canMoveForward: Bool
    public let canMoveBack: Bool
    public let commit: () -> Void
    public let move: (Int) -> Void
    public let delete: () -> Void
    public var close: (() -> Void)?
    @State private var tab = InspectorTab.content

    public var body: some View {
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

    public init(
        layer: OverlayLayer,
        canMoveForward: Bool,
        canMoveBack: Bool,
        commit: @escaping () -> Void,
        move: @escaping (Int) -> Void,
        delete: @escaping () -> Void,
        close: (() -> Void)? = nil
    ) {
        self.layer = layer
        self.canMoveForward = canMoveForward
        self.canMoveBack = canMoveBack
        self.commit = commit
        self.move = move
        self.delete = delete
        self.close = close
    }
}

/// Floating toolbar over the selected widget: edit, duplicate, bring forward, hide, delete.
public struct SceneSelectionBar: View {
    /// nil on iPad, where the inspector is always on screen.
    public let edit: (() -> Void)?
    public let duplicate: () -> Void
    public let forward: () -> Void
    public let hide: () -> Void
    public let delete: () -> Void

    public var body: some View {
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

    public init(
        edit: (() -> Void)? = nil,
        duplicate: @escaping () -> Void,
        forward: @escaping () -> Void,
        hide: @escaping () -> Void,
        delete: @escaping () -> Void
    ) {
        self.edit = edit
        self.duplicate = duplicate
        self.forward = forward
        self.hide = hide
        self.delete = delete
    }
}
