// Goal bar preview: title, "€312 / €800", a flat progress bar (the in-app editor's LayerPreview; the stream draws it on the GPU, GoalArt).
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
    /// The goal on the GPU (GoalArt.swift): the task in GoalPlayer.swift hands the GPU object a scene when the goal changes.
    func goalWidget(_ l: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        guard let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        let style = GoalWidgetStyle(l.data)
        let screen = await OverlayScreen.makeGPU(rect)
        // The box inside the widget's (visible) rect, in the rect's top-left coordinates.
        let local = CGRect(x: box.minX - rect.minX, y: box.minY - rect.minY, width: box.width, height: box.height)
        let task = Task { await GoalPlayer.run(style, on: screen, local: local) }
        let object: ScreenObject = screen
        return WidgetBuild(object: object, task: task)
    }
}
