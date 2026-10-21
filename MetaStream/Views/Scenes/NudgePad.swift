import SwiftUI

/// Four arrows that move the selected widget a hair at a time. Holding one repeats (after 0.4 s, then every 0.08 s).
/// `step` gets the move in layout fractions of the canvas (WidgetLayout dx/dy); `commit` runs when the finger lifts.
struct NudgePad: View {
    let step: (CGSize) -> Void
    let commit: () -> Void
    /// 0.25% of the canvas per step.
    static let amount: CGFloat = 0.0025
    private static let arrows: [(symbol: String, label: String, dir: CGSize)] = [
        ("arrow.up", "Nudge up", CGSize(width: 0, height: -1)), ("arrow.down", "Nudge down", CGSize(width: 0, height: 1)),
        ("arrow.left", "Nudge left", CGSize(width: -1, height: 0)), ("arrow.right", "Nudge right", CGSize(width: 1, height: 0))
    ]

    @State private var holding: Task<Void, Never>?
    /// Index of the arrow under the finger; a GestureState so it resets even when a scroll steals the touch.
    @GestureState private var pressed: Int?

    var body: some View {
        VStack(spacing: 8) {
            arrow(0)
            HStack(spacing: 8) {
                arrow(2)
                Color.clear.frame(width: 52, height: 44)
                arrow(3)
            }
            arrow(1)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: pressed) { if let idx = pressed { press(idx) } else { release() } }
        .onDisappear { release() }
    }

    private func arrow(_ idx: Int) -> some View {
        let item = Self.arrows[idx]
        return Image(systemName: item.symbol).font(.title3.weight(.semibold))
            .frame(width: 52, height: 44)
            .background(Color.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = idx })
            .accessibilityLabel(item.label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { step(scaled(item.dir)); commit() }
    }

    private func scaled(_ dir: CGSize) -> CGSize { CGSize(width: dir.width * Self.amount, height: dir.height * Self.amount) }

    private func press(_ idx: Int) {
        guard holding == nil else { return }
        hapticTap()
        let dir = scaled(Self.arrows[idx].dir)
        holding = Task {
            step(dir)
            try? await Task.sleep(for: .seconds(0.4))
            while !Task.isCancelled {
                step(dir)
                try? await Task.sleep(for: .seconds(0.08))
            }
        }
    }

    private func release() {
        guard let task = holding else { return }
        task.cancel()
        holding = nil
        commit()
    }
}
