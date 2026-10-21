// GoalHairlineView and GoalSparkView on the GPU: a line with a glowing tip, text above, a drop shadow under it all. Laid out
// in the SwiftUI views' points; the content hugs its side of the box (GoalArt.frame places it).
import CoreImage
import UIKit

extension GoalDraw {
    // MARK: Hairline

    /// GoalHairlineView: TITLE and percentage, a big rolling amount, "of target" and a 2 pt line with sweep, tip and "+delta" ghost.
    func hairline() -> GoalPiece {
        let roll = GoalMotion.lp(prog, 44, 52)
        let head = run(input.title.uppercased(), 11, .bold).tracked(2.2).fading(0.72)
        let big = run("", 32, .heavy).centred()
        let sub = run("of " + input.targetText, 14, .semibold).fading(0.6)
        let pct = GoalFlip(before: goalPct(input.from), after: goalPct(input.to), progress: roll, rise: 14, drop: -14, minWidth: 34)
        let amount = GoalFlip(before: input.beforeText, after: input.afterText, progress: roll, rise: 38, drop: -38, minWidth: 96)
        let row1 = metrics(head).width + (style.showPercent ? 24 + flipWidth(pct, head) : 0)
        let inner = max(340, row1, flipWidth(amount, big) + 8 + metrics(sub).width)
        let headH = max(metrics(head).height, style.showPercent ? 14 : 0)
        let row2 = 8 + headH + 6
        let bar = row2 + 38 + 6
        let base2 = row2 + 19 - metrics(big).height / 2 + metrics(big).asc
        var content: [CIImage] = [text(fit(head, width: inner - 24), x: 12, y: 8 + metrics(head).asc)]
        if style.showPercent {
            let cut = area(12 + inner - flipWidth(pct, head), 8 + metrics(head).height / 2 - 7, flipWidth(pct, head), 14)
            content.append(clipped(flip(pct, head, x: 12 + inner, y: 8 + metrics(head).asc, side: .trail), to: cut))
        }
        let cutBig = area(12, row2, flipWidth(amount, big), 38)
        content.append(clipped(flip(amount, big, x: 12, y: row2 + 19, side: .lead), to: cutBig))
        content.append(text(sub, x: 12 + flipWidth(amount, big) + 8, y: base2))
        content.append(moved(hairBar(inner), x: 12, y: bar))
        var layers: [CIImage] = []
        let wide = inner + 24, high = bar + 2 + 8
        if style.background { layers.append(pill(area(0, 0, wide, high), 12, style.backgroundColor)) }
        layers.append(shadowed(pen.stack(content), alpha: 0.55, dy: 1))
        return GoalPiece(image: pen.stack(layers), size: CGSize(width: wide, height: high))
    }

    /// The 2 pt line: track, accent fill with a white sweep, the bright tip with its glow, and the floating "+delta".
    private func hairBar(_ wide: CGFloat) -> CIImage {
        let fw = wide * CGFloat(level(GoalMotion.lp(prog, 40, 56)))
        let sweepX = CGFloat(GoalMotion.kf(prog, [(42, -0.3), (64, 1.05)])) * fw
        let sweepO = GoalMotion.kf(prog, [(42, 0), (46, 1), (64, 0)])
        let tip = CGFloat(GoalMotion.kf(prog, [(40, 1), (48, 1.8), (66, 1)]))
        let glowR = CGFloat(GoalMotion.kf(prog, [(40, 0), (48, 8), (66, 3)]))
        let ghostO = GoalMotion.kf(prog, [(42, 0), (48, 1), (70, 0)])
        let ghostY = CGFloat(GoalMotion.kf(prog, [(42, 4), (48, -6), (70, -22)]))
        let ghost = run(input.deltaText.isEmpty ? "" : "+" + input.deltaText, 13, .heavy).colored(accent).centred()
        let sweep = pen.stack([pen.linear(pt(sweepX, 0), pt(sweepX + 30, 0), Self.white, Self.white, alphaA: 0, alphaB: 1),
                               pen.linear(pt(sweepX + 30, 0), pt(sweepX + 60, 0), Self.white, Self.white, alphaA: 1, alphaB: 0)])
        let bright = clipped(pen.opacity(clipped(sweep, to: area(sweepX, 0, 60, 2)), sweepO), to: area(0, 0, fw, 2))
        let dot = disc(CGPoint(x: fw, y: 1), 3 * tip, Self.white)
        return pen.stack([fill(area(0, 0, wide, 2), Self.white, alpha: 0.14), capsule(area(0, 0, fw, 2), accent), bright,
                          glow(disc(CGPoint(x: fw, y: 1), 3 * tip, accent), accent, radius: glowR), dot,
                          text(ghost.fading(CGFloat(ghostO)), x: fw + 18, y: -22 + ghostY + metrics(ghost).height / 2, side: .trail)])
    }

    // MARK: Spark

    /// GoalSparkView: title and "total / target" over a 4 pt line whose tip flares and throws nine sparks.
    func spark() -> GoalPiece {
        let title = run(input.title, 13, .heavy)
        let amount = run("", 15, .heavy)
        let tail = run("/ " + input.targetText, 13, .semibold).fading(0.6)
        let spec = GoalFlip(before: input.beforeText, after: input.afterText, progress: GoalMotion.lp(prog, 50, 56), minWidth: 40)
        let amountW = flipWidth(spec, amount)
        let group = amountW + 4 + metrics(tail).width
        let inner = max(380, metrics(title).width + 24 + group)
        let rowAsc = max(metrics(title).asc, metrics(amount).asc, metrics(tail).asc)
        let rowH = rowAsc + max(metrics(title).height - metrics(title).asc, metrics(amount).height - metrics(amount).asc)
        let wide = inner + 24, high = 8 + rowH + 10 + 4 + 8
        let line = [text(fit(title, width: inner - group - 24), x: 12, y: 8 + rowAsc),
                    flip(spec, amount, x: 12 + inner - metrics(tail).width - 4, y: 8 + rowAsc, side: .trail),
                    text(tail, x: 12 + inner - metrics(tail).width, y: 8 + rowAsc), moved(sparkBar(inner), x: 12, y: 8 + rowH + 10)]
        var layers: [CIImage] = []
        if style.background { layers.append(pill(area(0, 0, wide, high), 12, style.backgroundColor)) }
        layers.append(shadowed(pen.stack(line), alpha: 0.55, dy: 1))
        return GoalPiece(image: pen.stack(layers), size: CGSize(width: wide, height: high))
    }

    /// The board's nine particle targets (x, y), up and back from the tip.
    private static let bitOffsets: [(CGFloat, CGFloat)] = [(-26, -22), (-40, -8), (-18, -34), (-48, -26), (-10, -18), (-34, 6),
                                                           (-22, 12), (-56, -4), (-6, -40)]
    private static let bits: [CGPoint] = bitOffsets.map { CGPoint(x: $0.0, y: $0.1) }

    private func sparkBar(_ wide: CGFloat) -> CIImage {
        let fw = wide * CGFloat(level(GoalMotion.lp(prog, 40, 52)))
        let flash = GoalMotion.kf(prog, [(40, 0), (50, 1), (66, 0)])
        let core = CGFloat(GoalMotion.kf(prog, [(40, 1), (52, 1.9), (70, 1)]))
        let coreGlow = CGFloat(GoalMotion.kf(prog, [(40, 5), (52, 12), (70, 5)]))
        let tip = CGPoint(x: fw, y: 2)
        var layers = [capsule(area(0, 0, wide, 4), Self.white, alpha: 0.12), capsule(area(0, 0, fw, 4), accent),
                      capsule(area(0, 0, fw, 4), Self.white, alpha: CGFloat(0.3 * flash)),
                      glow(disc(tip, 5 * core, accent), accent, radius: coreGlow), disc(tip, 5 * core, Self.white)]
        layers.append(contentsOf: Self.bits.indices.map { bit($0, fw) })
        return pen.stack(layers)
    }

    /// Particle i: appears at the tip, flies out (eased) and shrinks away, each 0.33 loop-% after the last.
    private func bit(_ index: Int, _ fw: CGFloat) -> CIImage {
        let late = Double(index) * 0.33
        let seen = GoalMotion.kf(prog, [(50, 0), (52, 1), (72, 0)], delay: late)
        let lin = GoalMotion.kf(prog, [(50, 0), (72, 1)], delay: late)
        let ease = CGFloat(1 - (1 - lin) * (1 - lin))
        let target = Self.bits[index]
        let spot = CGPoint(x: fw - 2 + target.x * ease + 2, y: target.y * ease + 2)
        let scale = 1 - 0.7 * CGFloat(lin)
        return pen.stack([glow(disc(spot, 2 * scale, accent), accent, radius: 3, alpha: seen),
                          disc(spot, 2 * scale, Self.white, alpha: CGFloat(seen))])
    }
}
