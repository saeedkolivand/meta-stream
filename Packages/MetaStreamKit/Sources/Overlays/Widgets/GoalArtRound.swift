// GoalIslandView, GoalMiniRingView and GoalDotsView on the GPU, in the SwiftUI views' points. Progress rings are an arc mask
// (StingerCanvas.glArc: one cached stroke, revealed on the GPU), so a ring that fills costs no CPU.
import CoreImage
import UIKit

extension GoalDraw {
    private func width(_ text: String, _ size: CGFloat, _ weight: UIFont.Weight, _ spacing: CGFloat = 0) -> CGFloat {
        metrics(run(text, size, weight).tracked(spacing)).width
    }

    // MARK: Island pill

    /// GoalIslandView: a pill with a ring and "total / target" that bursts open on a donation to show the title and "+delta".
    func island() -> GoalPiece {
        let amountW = max(width(input.beforeText, 15, .heavy), width(input.afterText, 15, .heavy))
        let rest = 10 + 26 + 10 + amountW + width(" / " + input.targetText, 15, .semibold) + 16 + 8
        let titleW = width(input.title.uppercased(), 11, .semibold, 0.88)
        let lineW = width(input.afterText, 17, .heavy) + width(" / " + input.targetText, 14, .semibold)
        let burst = max(12 + 32 + 10 + max(titleW, lineW) + 16 + width("+" + input.deltaText, 20, .heavy) + 18 + 10, rest + 60)
        let rise = GoalMotion.seg(prog, 0, 0.2) - 1
        let spring = 1 + 2.2 * rise * rise * rise + 1.2 * rise * rise   // overshoot
        let swell = CGFloat(spring * (1 - GoalMotion.smooth(GoalMotion.seg(prog, 0.75, 1))))
        let wide = rest + (burst - rest) * swell, high = 44 + 12 * swell
        let shown = level(GoalMotion.smooth(GoalMotion.seg(prog, 0.12, 0.55)))
        let glowing = GoalMotion.seg(prog, 0, 0.12) * (1 - GoalMotion.seg(prog, 0.12, 0.7))
        let restO = min(1, (1 - GoalMotion.seg(prog, 0, 0.08)) + GoalMotion.seg(prog, 0.78, 0.9))
        let burstO = GoalMotion.seg(prog, 0.03, 0.18) * (1 - GoalMotion.seg(prog, 0.7, 0.8))
        let shape = area(0, 0, wide, high)
        let inside = pen.stack([pen.opacity(restLayer(shown, amountW, high), restO),
                                pen.opacity(burstLayer(shown, wide, high), burstO)])
        var layers = [glow(capsule(shape, accent), accent, radius: 14, alpha: 0.8 * glowing)]
        if style.background { layers.append(capsule(shape, style.backgroundColor)) }
        layers.append(clipped(inside, to: shape))
        return GoalPiece(image: pen.stack(layers), size: CGSize(width: wide, height: high))
    }

    private func restLayer(_ shown: Double, _ amountW: CGFloat, _ high: CGFloat) -> CIImage {
        let amount = run(prog < 0.5 ? input.beforeText : input.afterText, 15, .heavy).centred()
        let tail = run(" / " + input.targetText, 15, .semibold).fading(0.55).centred()
        return pen.stack([ring(26, shown, at: CGPoint(x: 23, y: high / 2)), text(amount, x: 46, y: high / 2),
                          text(tail, x: 46 + amountW, y: high / 2)])
    }

    private func burstLayer(_ shown: Double, _ wide: CGFloat, _ high: CGFloat) -> CIImage {
        let title = run(input.title.uppercased(), 11, .semibold).tracked(0.88).fading(0.65).centred()
        let after = run(input.afterText, 17, .heavy)
        let tail = run(" / " + input.targetText, 14, .semibold).fading(0.55)
        let asc = max(metrics(after).asc, metrics(tail).asc)
        let lineH = asc + max(metrics(after).height - metrics(after).asc, metrics(tail).height - metrics(tail).asc)
        let titleH = metrics(title).height
        let top = high / 2 - (titleH + 1 + lineH) / 2
        let plus = run("+" + input.deltaText, 20, .heavy).colored(accent).centred()
        let layer = pen.stack([ring(32, shown, at: CGPoint(x: 28, y: high / 2)), text(title, x: 54, y: top + titleH / 2),
                               text(after, x: 54, y: top + titleH + 1 + asc),
                               text(tail, x: 54 + metrics(after).width, y: top + titleH + 1 + asc),
                               text(plus, x: wide - 18, y: high / 2, side: .trail)])
        let grow = 0.92 + 0.08 * CGFloat(GoalMotion.seg(prog, 0.03, 0.18))
        return pen.transform(layer, about: pt(wide / 2, high / 2), scale: grow)
    }

    // MARK: Mini ring

    /// GoalMiniRingView: a 72 pt ring (comet and pulse on a donation) with the title, amount and "+delta just now" beside it.
    func miniRing() -> GoalPiece {
        let shown = level(GoalMotion.lp(prog, 42, 60))
        let swap = GoalMotion.lp(prog, 56, 62)
        let title = run(input.title.uppercased(), 11, .semibold).tracked(1.54).fading(0.65)
        let amount = run("", 18, .heavy)
        let tail = run("of " + input.targetText, 14, .semibold).fading(0.55)
        let delta = run(input.deltaText.isEmpty ? " " : "+\(input.deltaText) just now", 12, .heavy).colored(accent)
        let spec = GoalFlip(before: input.beforeText, after: input.afterText, progress: swap, minWidth: 44)
        let asc = max(metrics(amount).asc, metrics(tail).asc)
        let lineH = asc + max(metrics(amount).height - metrics(amount).asc, metrics(tail).height - metrics(tail).asc)
        let colH = metrics(title).height + 2 + lineH + 2 + metrics(delta).height
        let colW = max(metrics(title).width, flipWidth(spec, amount) + 4 + metrics(tail).width, metrics(delta).width)
        let wide = 10 + 72 + 14 + colW + 18, high = max(72, colH) + 20
        let top = high / 2 - colH / 2, lineTop = top + metrics(title).height + 2
        let plusO = CGFloat(GoalMotion.kf(prog, [(42, 0), (48, 1), (70, 1), (75, 0)]))
        let plusY = CGFloat(GoalMotion.kf(prog, [(42, 6), (48, 0), (70, 0), (75, -6)]))
        var layers: [CIImage] = []
        if style.background { layers.append(capsule(area(0, 0, wide, high), style.backgroundColor)) }
        layers.append(contentsOf: [ringBlock(shown, swap, at: CGPoint(x: 46, y: high / 2)),
                                   text(title.centred(), x: 96, y: top + metrics(title).height / 2),
                                   flip(spec, amount, x: 96, y: lineTop + asc, side: .lead),
                                   text(tail, x: 96 + flipWidth(spec, amount) + 4, y: lineTop + asc),
                                   text(delta.centred().fading(plusO), x: 96, y: lineTop + lineH + 2 + metrics(delta).height / 2 + plusY)])
        return GoalPiece(image: pen.stack(layers), size: CGSize(width: wide, height: high))
    }

    private func ringBlock(_ shown: Double, _ swap: Double, at centre: CGPoint) -> CIImage {
        let pulse = CGFloat(GoalMotion.kf(prog, [(58, 0.9), (75, 1.45)]))
        let pulseO = CGFloat(GoalMotion.kf(prog, [(58, 0), (61, 0.8), (75, 0)]))
        let cometO = GoalMotion.kf(prog, [(41, 0), (43, 1), (60, 1), (68, 0)])
        let ang = 2 * Double.pi * shown
        let comet = CGPoint(x: centre.x + 30 * CGFloat(sin(ang)), y: centre.y - 30 * CGFloat(cos(ang)))
        let spec = GoalFlip(before: goalPct(input.from), after: goalPct(input.to), progress: swap, minWidth: 40)
        return pen.stack([outline(centre, 36 * pulse, width: 2 * pulse, accent, alpha: pulseO),
                          outline(centre, 32.5, width: 5, style.trackColor),
                          arc(30, width: 5, fraction: min(1, max(0, shown)), at: centre, accent),
                          glow(disc(comet, 5, accent), accent, radius: 11, alpha: cometO),
                          glow(disc(comet, 5, accent), accent, radius: 5, alpha: cometO),
                          disc(comet, 5, Self.white, alpha: CGFloat(cometO)),
                          flip(spec, run("", 17, .heavy).centred(), x: centre.x, y: centre.y, side: .center)])
    }

    // MARK: Dot wave

    /// GoalDotsView: title and amounts over a row of 24 dots that ripple and pop on a donation.
    func dots() -> GoalPiece {
        let count = 24
        let nb = min(count, max(0, Int((input.from * Double(count)).rounded())))
        let na = min(count, max(nb, Int((input.to * Double(count)).rounded())))
        let title = run(input.title.uppercased(), 11, .semibold).tracked(1.76).fading(0.65)
        let amount = run("", 15, .heavy)
        let tail = run("/ " + input.targetText, 13, .semibold).fading(0.55)
        let spec = GoalFlip(before: input.beforeText, after: input.afterText, progress: GoalMotion.lp(prog, 52, 58), minWidth: 40)
        let group = flipWidth(spec, amount) + 4 + metrics(tail).width
        let inner = max(metrics(title).width + 20 + group, 307)
        let asc = max(metrics(title).asc, metrics(amount).asc, metrics(tail).asc)
        let headH = asc + max(metrics(title).height - metrics(title).asc, metrics(amount).height - metrics(amount).asc)
        let wide = inner + 32, high = 12 + headH + 9 + 8 + 12
        let plusO = CGFloat(GoalMotion.kf(prog, [(48, 0), (54, 1), (66, 1), (75, 0)]))
        let plusX = CGFloat(GoalMotion.kf(prog, [(48, -6), (54, 0)]))
        let plus = run(input.deltaText.isEmpty ? "" : "+" + input.deltaText, 12, .heavy).colored(accent).centred().fading(plusO)
        let right = 16 + inner
        var layers: [CIImage] = []
        if style.background { layers.append(pill(area(0, 0, wide, high), 14, style.backgroundColor)) }
        layers.append(contentsOf: [text(title, x: 16, y: 12 + asc),
                                   flip(spec, amount, x: right - metrics(tail).width - 4, y: 12 + asc, side: .trail),
                                   text(tail, x: right - metrics(tail).width, y: 12 + asc),
                                   text(plus, x: right - group - 8 + plusX, y: 12 + headH / 2, side: .trail)])
        layers.append(contentsOf: (0..<count).map { dot($0, nb, na, at: CGPoint(x: 20 + CGFloat($0) * 13, y: 12 + headH + 9 + 4)) })
        return GoalPiece(image: pen.stack(layers), size: CGSize(width: wide, height: high))
    }

    /// Lit dots ripple (scale + brightness, each a little after the last); new dots pop white, then settle to the accent.
    private func dot(_ index: Int, _ nb: Int, _ na: Int, at centre: CGPoint) -> CIImage {
        let lit = index < nb
        let isNew = index >= nb && index < na
        let late = Double(index) * 0.58
        let newLate = Double(min(8, max(0, index - nb)))
        let wave = lit ? GoalMotion.kf(prog, [(40, 0), (44, 1), (50, 0)], delay: late) : 0
        let pop = isNew ? GoalMotion.kf(prog, [(50, 1), (54, 1.9), (60, 1)], delay: newLate) : 1
        let white = isNew ? GoalMotion.kf(prog, [(50, 0), (54, 1)], delay: newLate) : 0
        let settled = lit ? 1 : (isNew ? GoalMotion.kf(prog, [(54, 0), (60, 1)], delay: newLate) : 0)
        let radius = 4 * (lit ? 1 + 0.7 * CGFloat(wave) : CGFloat(pop))
        return pen.stack([disc(centre, radius, style.trackColor), disc(centre, radius, Self.white, alpha: CGFloat(white)),
                          disc(centre, radius, accent, alpha: CGFloat(settled)),
                          disc(centre, radius, Self.white, alpha: CGFloat(0.3 * wave))])
    }
}
