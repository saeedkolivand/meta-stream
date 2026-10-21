import SwiftUI

/// The Position tab: a 3x3 anchor grid, size, stacking order, visibility, name and delete.
extension WidgetInspectorView {
    private static let anchorNames = ["Top left", "Top centre", "Top right", "Middle left", "Centre", "Middle right",
                                      "Bottom left", "Bottom centre", "Bottom right"]

    @ViewBuilder var positionTab: some View {
        if let layout = layer.layout {
            Section {
                anchorGrid(current: layout.anchor)
            } header: { Text("Anchor") } footer: {
                Text("Snaps the widget to that spot with the standard safe margin. Drag it on the canvas for anything in between.")
            }
        }
        Section("Size") {
            slider("Size", sizeBinding, 0.05...4, format: "%.2f×")
        }
        Section("Layer") {
            TextField("Name", text: $layer.name)
            Toggle("Visible", isOn: $layer.visible)
            HStack {
                Button { move(1) } label: { Label("Bring forward", systemImage: "square.2.layers.3d.top.filled") }.disabled(!canMoveForward)
                Spacer()
                Button { move(-1) } label: { Label("Send back", systemImage: "square.2.layers.3d.bottom.filled") }.disabled(!canMoveBack)
            }
            .buttonStyle(.borderless)
            Button("Delete layer", role: .destructive, action: delete)
        }
    }

    /// Rows of three: tapping a cell resets the layout to that anchor's default inset (offset gone), keeping the size.
    private func anchorGrid(current: Int) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in anchorCell(row * 3 + col, current: current) }
                }
            }
        }
        .frame(maxWidth: 240)
        .frame(maxWidth: .infinity)
    }

    private func anchorCell(_ anchor: Int, current: Int) -> some View {
        Button {
            hapticTap()
            layer.layout = .inset(anchor, scale: layer.layout?.scale ?? 1)
            commit()
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .fill(anchor == current ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Self.anchorNames[anchor])
        .accessibilityAddTraits(anchor == current ? .isSelected : [])
    }

    var sizeBinding: Binding<Double> {
        Binding {
            Double(layer.layout?.scale ?? layer.sx)
        } set: { value in
            if layer.layout != nil {
                layer.layout?.scale = CGFloat(value)
            } else {
                // OBS layers: scale both axes by the same ratio so the aspect holds
                let ratio = layer.sx > 0 ? CGFloat(value) / layer.sx : 1
                layer.sx *= ratio; layer.sy *= ratio
            }
        }
    }
}
