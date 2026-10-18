// Native goal bar: title, "€312 / €800", a flat progress bar. Redrawn only when the total, the goal or the celebration changes.
import HaishinKit
import SwiftUI

struct GoalView: View {
    let style: GoalWidgetStyle
    let title: String
    let totalText: String
    let targetText: String
    let progress: Double
    let otherText: String
    let celebrating: Bool

    private func c(_ argb: UInt32) -> Color { Color(uiColor: OverlayRaster.color(argb: argb)) }

    var body: some View {
        let size = CGFloat(style.fontSize)
        let shown = celebrating ? "Goal reached!" : title
        let p = min(1, max(0, progress))
        VStack(alignment: .leading, spacing: size * 0.3) {
            HStack(spacing: 12) {
                Text(shown).lineLimit(1).environment(\.layoutDirection, WidgetFonts.isRTL(shown) ? .rightToLeft : .leftToRight)
                Spacer(minLength: 8)
                Text("\(totalText) / \(targetText)").lineLimit(1)
            }
            .font(WidgetFonts.font(face: style.face, size: size, weight: .bold))
            .foregroundColor(c(style.textColor))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(c(style.trackColor))
                    Capsule().fill(c(celebrating ? style.textColor : style.barColor)).frame(width: g.size.width * p)
                }
            }
            .frame(height: size * 0.6)
            HStack {
                if style.showOther && !otherText.isEmpty { Text(otherText).lineLimit(1) }
                Spacer(minLength: 8)
                if style.showPercent { Text("\(Int((progress * 100).rounded()))%") }
            }
            .font(WidgetFonts.font(face: style.face, size: size * 0.7, weight: .semibold))
            .foregroundColor(c(style.textColor).opacity(0.85))
        }
        .padding(16)
        .frame(width: CGFloat(style.width), height: CGFloat(style.height), alignment: .center)
        .background { if style.background { RoundedRectangle(cornerRadius: 14).fill(c(style.backgroundColor)) } }
    }

    static func sample(_ style: GoalWidgetStyle) -> GoalView {
        GoalView(style: style, title: "New camera", totalText: "€312", targetText: "€800", progress: 0.39,
                 otherText: "≈ ₮33,700,000 · $337", celebrating: false)
    }
}

extension OverlayCompositor {
    func goalWidget(_ l: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        guard let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        let style = GoalWidgetStyle(l.data)
        let natural = style.natural
        let o = await OverlayScreen.makeImage(rect, nil)
        let task = Task {
            var last = ""
            var wasReached = GoalStore.shared.reached
            var reachedAt: Date?
            while !Task.isCancelled {
                let store = GoalStore.shared
                let cfg = store.config
                if store.reached != wasReached { wasReached = store.reached; reachedAt = store.reached ? Date() : nil }
                let celebrating = store.reached && (reachedAt.map { Date().timeIntervalSince($0) < 6 } ?? false)
                let sig = "\(store.total)|\(cfg.target)|\(cfg.title)|\(cfg.currency)|\(store.reached)|\(celebrating)"
                if sig != last {
                    last = sig
                    let other = ["IRT", "USD", "EUR"].filter { $0 != cfg.currency }.compactMap { code in
                        Rates.shared.convert(Money(store.total, cfg.currency), to: code).map { Money($0, code).display }
                    }
                    let view = GoalView(style: style, title: cfg.title, totalText: Money(store.total, cfg.currency).display,
                                        targetText: Money(cfg.target, cfg.currency).display, progress: store.progress,
                                        otherText: other.isEmpty ? "" : "≈ " + other.joined(separator: " · "), celebrating: celebrating)
                    let piece = WidgetRaster.piece(view, natural: natural, box: box, canvas: canvas)
                    await OverlayScreen.setImage(o, piece?.bitmap)
                }
                try? await Task.sleep(for: WidgetRaster.pause(500))
            }
        }
        let object: ScreenObject = o
        return WidgetBuild(object: object, task: task)
    }
}
