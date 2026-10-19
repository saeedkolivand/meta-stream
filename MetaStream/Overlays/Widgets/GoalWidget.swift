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
        let design = style.design
        let task = Task {
            var last = ""
            var wasReached = GoalStore.shared.reached
            var reachedAt: Date?
            var shownTotal = GoalStore.shared.total   // what the new designs show; a rise above it plays a reaction
            var shownP = GoalStore.shared.progress
            while !Task.isCancelled {
                let store = GoalStore.shared
                let cfg = store.config
                if store.reached != wasReached { wasReached = store.reached; reachedAt = store.reached ? Date() : nil }
                let celebrating = store.reached && (reachedAt.map { Date().timeIntervalSince($0) < 6 } ?? false)
                let sig = "\(store.total)|\(cfg.target)|\(cfg.title)|\(cfg.currency)|\(store.reached)|\(celebrating)"
                if sig != last {
                    last = sig
                    if design == "bar" {
                        let other = ["IRT", "USD", "EUR"].filter { $0 != cfg.currency }.compactMap { code in
                            Rates.shared.convert(Money(store.total, cfg.currency), to: code).map { Money($0, code).display }
                        }
                        let view = GoalView(style: style, title: cfg.title, totalText: Money(store.total, cfg.currency).display,
                                            targetText: Money(cfg.target, cfg.currency).display, progress: store.progress,
                                            otherText: other.isEmpty ? "" : "≈ " + other.joined(separator: " · "), celebrating: celebrating)
                        let piece = WidgetRaster.piece(view, natural: natural, box: box, canvas: canvas)
                        await OverlayScreen.setImage(o, piece?.bitmap)
                    } else {
                        let title = celebrating ? "Goal reached!" : cfg.title
                        let pins = [25, 50, 75].map { Money(cfg.target * Decimal($0) / 100, cfg.currency).display }
                        func draw(_ a: Decimal, _ b: Decimal, _ fromP: Double, _ toP: Double, _ t: Double) async {
                            let view = GoalDesignView(style: style, title: title, beforeText: Money(a, cfg.currency).display,
                                                      afterText: Money(b, cfg.currency).display,
                                                      targetText: Money(cfg.target, cfg.currency).display, from: fromP, to: toP,
                                                      deltaText: b > a ? Money(b - a, cfg.currency).display : "", t: t,
                                                      pins: pins, celebrating: celebrating)
                            let piece = WidgetRaster.piece(view, natural: natural, box: box, canvas: canvas)
                            await OverlayScreen.setImage(o, piece?.bitmap)
                        }
                        let total = store.total
                        if total > shownTotal {
                            // A donation arrived: play the reaction (t 0...1 over 1.6 s). If the total moves again, restart from what is shown.
                            var fromTotal = shownTotal, fromP = shownP
                            var toTotal = total, toP = store.progress
                            var t0 = Date()
                            while !Task.isCancelled {
                                let now = store.total
                                if now < toTotal { break }   // refund mid-reaction: the next poll redraws statically
                                if now != toTotal {
                                    let t = min(1, Date().timeIntervalSince(t0) / 1.6)
                                    fromP += (toP - fromP) * GoalMotion.move(t)
                                    if t >= 0.5 { fromTotal = toTotal }
                                    toTotal = now; toP = store.progress; t0 = Date()
                                }
                                let t = min(1, Date().timeIntervalSince(t0) / 1.6)
                                await draw(fromTotal, toTotal, fromP, toP, t)
                                if t >= 1 { break }
                                try? await Task.sleep(for: WidgetRaster.pause(33))
                            }
                            shownTotal = toTotal; shownP = toP
                            if store.total != toTotal { last = "" }
                        } else {
                            shownTotal = total; shownP = store.progress
                            await draw(total, total, shownP, shownP, 1)
                        }
                    }
                }
                try? await Task.sleep(for: WidgetRaster.pause(500))
            }
        }
        let object: ScreenObject = o
        return WidgetBuild(object: object, task: task)
    }
}
