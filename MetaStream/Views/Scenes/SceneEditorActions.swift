import SwiftUI

/// What the editor does to its working copy of the layers, and how that reaches the store.
extension SceneEditorView {
    func append(_ layer: OverlayLayer) {
        layers.append(layer)
        selected = layers.count - 1
        hapticTap()
        saveNow()
    }

    func remove(_ index: Int) {
        guard layers.indices.contains(index) else { return }
        layers.remove(at: index)
        selected = nil
        hapticTap()
        saveNow()
    }

    /// A copy a little down and right of the original, selected.
    func duplicate(_ index: Int) {
        guard layers.indices.contains(index) else { return }
        var copy = layers[index]
        copy.name += " copy"
        if copy.layout != nil {
            copy.layout?.dx += 0.03
            copy.layout?.dy += 0.03
        } else {
            copy.x += 40
            copy.y += 40
        }
        append(copy)
    }

    func hide(_ index: Int) {
        guard layers.indices.contains(index) else { return }
        layers[index].visible = false
        saveNow()
    }

    /// Swaps with the neighbour: +1 brings forward, -1 sends back.
    func move(_ index: Int, _ by: Int) {
        let target = index + by
        guard layers.indices.contains(index), layers.indices.contains(target) else { return }
        layers.swapAt(index, target)
        selected = target
        saveNow()
    }

    /// Drag-reorder in the layer list, which shows the top layer first: `from`/`to` index that reversed order.
    func reorder(_ from: IndexSet, _ to: Int) {
        var order = Array(layers.indices.reversed())
        let pick = selected
        order.move(fromOffsets: from, toOffset: to)
        let bottomUp = Array(order.reversed())
        layers = bottomUp.map { layers[$0] }
        selected = pick.flatMap { bottomUp.firstIndex(of: $0) }
        saveNow()
    }

    func renameIfNeeded() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != name else { draftName = name; return }
        if store.renameScene(name, to: trimmed) { name = trimmed; draftName = trimmed } else { draftName = name }
    }

    /// Debounced: sliders, colour pickers and typing change the layers many times a second, and every save rebuilds
    /// the scene on stream.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { saveNow() }
        }
    }

    /// Autosave path: skipped while this scene is on stream (the draft waits for "Apply").
    func saveNow() {
        saveTask?.cancel()
        if !liveLocked { applyNow() }
    }

    func applyNow() {
        saveTask?.cancel()
        if layers != stored { store.setLayers(layers, in: name) }
    }
}
