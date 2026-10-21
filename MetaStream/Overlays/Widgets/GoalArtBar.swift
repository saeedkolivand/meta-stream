// GoalView (the bar) and GoalLiquidView on the GPU. Same geometry as the SwiftUI views, in their points.
import CoreImage
import UIKit

extension GoalDraw {
    /// GoalView: title and "total / target" over a flat capsule bar, other currencies and the percentage under it.
    func bar() -> GoalPiece {
        let wide = style.width, high = style.height, size = style.fontSize
        let progress = input.to
        let celebrating = input.celebrating
        let total = run("\(input.afterText) / \(input.targetText)", size, .bold, face: style.face).centred()
        let title = fit(run(celebrating ? "Goal reached!" : input.title, size, .bold, face: style.face).centred(),
                        width: wide - 32 - 12 - 8 - metrics(total).width)
        let note = run(input.otherText, size * 0.7, .semibold, face: style.face).fading(0.85).centred()
        let hasNote = style.showOther && !input.otherText.isEmpty
        let headH = metrics(title).height, gap = size * 0.3, barH = size * 0.6
        let footH = hasNote || style.showPercent ? metrics(note).height : 0
        let top = (high - (headH + gap + barH + gap + footH)) / 2
        let barY = top + headH + gap, footY = barY + barH + gap + footH / 2
        let percent = note.with("\(Int((progress * 100).rounded()))%")
        var layers: [CIImage] = []
        if style.background { layers.append(pill(area(0, 0, wide, high), 14, style.backgroundColor)) }
        layers.append(contentsOf: [text(title, x: 16, y: top + headH / 2), text(total, x: wide - 16, y: top + headH / 2, side: .trail),
                                   capsule(area(16, barY, wide - 32, barH), style.trackColor),
                                   capsule(area(16, barY, (wide - 32) * CGFloat(min(1, max(0, progress))), barH),
                                           celebrating ? style.textColor : accent)])
        if hasNote { layers.append(text(note, x: 16, y: footY)) }
        if style.showPercent { layers.append(text(percent, x: wide - 16, y: footY, side: .trail)) }
        return GoalPiece(image: pen.stack(layers), size: CGSize(width: wide, height: high))
    }

    /// A run in the text colour.
    func run(_ text: String, _ size: CGFloat, _ weight: UIFont.Weight, face: String = "Manrope") -> GoalRun {
        GoalRun(text: text, size: size, weight: weight, face: face, color: style.textColor)
    }

    // MARK: Liquid

    /// GoalLiquidView: title and amounts over a capsule tank whose fill has waves, bubbles and a splash ring.
    func liquid() -> GoalPiece {
        let swap = GoalMotion.seg(prog, 0.2, 0.5)
        let filled = level(GoalMotion.move(prog))
        let title = run(input.title, 17, .bold, face: "Unbounded")
        let amount = run("", 17, .heavy)
        let tail = amount.with("/ " + input.targetText).fading(0.77)
        let ink = max(metrics(title).asc, metrics(amount).asc)
        let head = ink + max(metrics(title).height - metrics(title).asc, metrics(amount).height - metrics(amount).asc)
        let top = (76 - (head + 7 + 34)) / 2
        let flipSpec = GoalFlip(before: input.beforeText, after: input.afterText, progress: swap)
        let amountRight = 410 - metrics(tail).width - 8
        let titleRoom = amountRight - flipWidth(flipSpec, amount) - 8 - 8 - 10
        var layers: [CIImage] = []
        if style.background { layers.append(pill(area(0, 0, 420, 76), 14, style.backgroundColor)) }
        layers.append(contentsOf: [text(fit(title, width: titleRoom), x: 10, y: top + ink),
                                   flip(flipSpec, amount, x: amountRight, y: top + ink, side: .trail),
                                   text(tail, x: 410, y: top + ink, side: .trail),
                                   moved(tank(filled, swap), x: 10, y: top + head + 7)])
        return GoalPiece(image: pen.stack(layers), size: CGSize(width: 420, height: 76))
    }

    /// The tank in its own 400x34 coordinates.
    private func tank(_ fraction: Double, _ swap: Double) -> CIImage {
        let wide: CGFloat = 400, high: CGFloat = 34
        let fw = wide * CGFloat(fraction)
        let phase = CGFloat((prog * 64).truncatingRemainder(dividingBy: 64))
        let splashT = GoalMotion.seg(prog, 0.1, 1)
        let splash = splashT < 0.17 ? splashT / 0.17 * 0.9 : 0.9 * (1 - (splashT - 0.17) / 0.83)
        let grow = CGFloat(0.4 + 1.2 * splashT)
        var water = [fill(area(0, 7, fw, high - 7), accent), wave(phase, accent, 1, y: 0)]
        water.append(wave((96 - phase).truncatingRemainder(dividingBy: 64), Self.white, 0.45, y: 2))
        water.append(contentsOf: (0..<6).map { bubble($0, fw, high) })
        var layers = [capsule(area(0, 0, wide, high), style.trackColor), clipped(pen.stack(water), to: area(0, 0, fw, high))]
        layers.append(outline(CGPoint(x: fw, y: 17), 14 * grow, width: 2 * grow, Self.white, alpha: splash))
        layers.append(capsuleBorder(area(0, 0, wide, high), width: 2, Self.white, alpha: 0.08))
        if style.showPercent {
            let spec = GoalFlip(before: goalPct(input.from), after: goalPct(input.to), progress: swap)
            layers.append(flip(spec, run("", 14, .heavy).centred(), x: wide - 12, y: 17, side: .trail))
        }
        return clipped(pen.stack(layers), to: area(0, 0, wide, high))
    }

    /// The board's quadratic crest: 8 periods of 64 points, rasterised once and slid by `phase`.
    private func wave(_ phase: CGFloat, _ argb: UInt32, _ alpha: CGFloat, y: CGFloat) -> CIImage {
        let unit = self.unit
        let strip = pen.glShape("gl.wave|\(Int(unit * 100))", size: CGSize(width: 512 * unit, height: 16 * unit)) { ctx in
            ctx.scaleBy(x: unit, y: unit)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.move(to: CGPoint(x: 0, y: 8))
            for step in 0..<16 {
                let x = CGFloat(step) * 32
                ctx.addQuadCurve(to: CGPoint(x: x + 32, y: 8), control: CGPoint(x: x + 16, y: step % 2 == 0 ? 0 : 16))
            }
            ctx.addLine(to: CGPoint(x: 512, y: 16))
            ctx.addLine(to: CGPoint(x: 0, y: 16))
            ctx.fillPath()
        }
        return tinted(moved(strip, x: -64 + phase, y: y), argb, alpha: alpha)
    }

    private func bubble(_ index: Int, _ fw: CGFloat, _ high: CGFloat) -> CIImage {
        let life = (prog * 0.9 + Double(index) * 0.17).truncatingRemainder(dividingBy: 1)
        let fade = life < 0.2 ? life / 0.2 * 0.8 : 0.8 * (1 - life) / 0.8
        let scale = 0.6 + 0.4 * CGFloat(life)
        let centre = CGPoint(x: fw * CGFloat(0.1 + 0.16 * Double(index)), y: high - 6 - 30 * CGFloat(life))
        return outline(centre, 3 * scale, width: 1.5 * scale, Self.white, alpha: 0.7 * CGFloat(fade))
    }
}
