import SwiftUI

extension View {
    /// Adds an expand button to a preview; it opens `full` (a fresh copy of the same live preview) as large as the
    /// screen allows. The stream is 16:9, so it is letterboxed on black; rotating just makes it bigger.
    func fullScreenPreview<Full: View>(@ViewBuilder _ full: @escaping () -> Full) -> some View {
        modifier(FullScreenPreviewModifier(full: full))
    }
}

private struct FullScreenPreviewModifier<Full: View>: ViewModifier {
    let full: () -> Full
    @State private var open = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                Button { open = true } label: { chip("arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Full screen preview")
            }
            .fullScreenCover(isPresented: $open) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    full().aspectRatio(16 / 9, contentMode: .fit).clipped()
                }
                .overlay(alignment: .topTrailing) {
                    Button { open = false } label: { chip("xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Close preview")
                }
            }
    }

    /// A 44 pt target with a small dark disc, so it reads over any preview.
    private func chip(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.footnote.weight(.bold)).foregroundStyle(.white)
            .frame(width: 30, height: 30).background(.black.opacity(0.55), in: Circle())
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }
}
