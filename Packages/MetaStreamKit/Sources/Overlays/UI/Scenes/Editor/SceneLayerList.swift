import SwiftUI

/// The scene's layers, top of the stack first: tap to select, eye to hide, swipe to delete, Edit to drag-reorder.
/// Used in the iPhone Layers sheet and the iPad left pane.
struct SceneLayerList: View {
    @Binding var layers: [OverlayLayer]
    @Binding var selected: Int?
    let delete: (Int) -> Void
    let reorder: (IndexSet, Int) -> Void
    @State private var editMode: EditMode = .inactive

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Spacer()
                if !layers.isEmpty {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 16)
            List {
                if layers.isEmpty {
                    Text("Nothing here yet. Tap + to add chat, alerts, text, an image and more.").foregroundStyle(.secondary)
                }
                ForEach(Array(layers.indices.reversed()), id: \.self) { row($0) }
                    .onMove(perform: reorder)
            }
            .listStyle(.plain)
        }
        .environment(\.editMode, $editMode)
    }

    private func row(_ idx: Int) -> some View {
        HStack {
            Button { selected = idx } label: {
                HStack {
                    Image(systemName: layers[idx].type.icon).frame(width: 26).foregroundStyle(.tint)
                    Text(layers[idx].name).foregroundStyle(layers[idx].visible ? .primary : .secondary)
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            Button { layers[idx].visible.toggle() } label: {
                Image(systemName: layers[idx].visible ? "eye" : "eye.slash").frame(width: 44, height: 44)
            }
            .accessibilityLabel(layers[idx].visible ? "Hide \(layers[idx].name)" : "Show \(layers[idx].name)")
        }
        .buttonStyle(.borderless)
        .listRowBackground(selected == idx ? Color.accentColor.opacity(0.2) : Color.clear)
        .swipeActions {
            Button(role: .destructive) { delete(idx) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}
