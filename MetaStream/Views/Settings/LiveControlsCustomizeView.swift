import SwiftUI

/// Which controls the strip in ContentView shows, and in what order -- writes the one
/// liveCameraControlOrder key CameraSettings.LiveCameraControl.order(from:) parses. List + .onMove +
/// EditButton is the idiomatic SwiftUI reorder pattern; .onDelete doubles as "remove from the strip" (still
/// reachable via swipe even without tapping Edit) and guards against emptying the list outright -- dropping
/// to zero controls would mean the camera button in ContentView opens onto nothing, with no way back short
/// of finding this screen blind, so removal below a floor of one is refused, and "Restore defaults" is
/// always one tap away as the other way back in.
struct LiveControlsCustomizeView: View {
    @AppStorage(LiveCameraControl.storageKey) private var orderRaw = LiveCameraControl.defaultOrderRaw
    @State private var order: [LiveCameraControl] = []

    private var available: [LiveCameraControl] { LiveCameraControl.allCases.filter { !order.contains($0) } }

    var body: some View {
        List {
            Section {
                ForEach(order, id: \.self) { Text($0.label) }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1); save() }
                    .onDelete { offsets in
                        guard order.count - offsets.count >= 1 else { return }   // guard the trap -- see type doc
                        order.remove(atOffsets: offsets)
                        save()
                    }
            } header: { Text("On the strip") } footer: {
                Text("Drag to reorder, or swipe to remove. At least one control stays on.")
            }

            if !available.isEmpty {
                Section("Available") {
                    ForEach(available, id: \.self) { control in
                        Button { order.append(control); save() } label: {
                            Label(control.label, systemImage: "plus.circle")
                        }
                    }
                }
            }

            Section("Preview") {
                Text(order.isEmpty ? "Nothing shown" : order.map(\.label).joined(separator: "  ·  "))
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Button("Restore defaults") { order = LiveCameraControl.defaultOrder; save() }
            }
        }
        .navigationTitle("Customise controls")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton() } }
        .onAppear { order = LiveCameraControl.order(from: orderRaw) }
    }

    private func save() { orderRaw = order.map(\.rawValue).joined(separator: ",") }
}
