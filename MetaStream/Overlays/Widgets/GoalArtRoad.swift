// GoalRoadView and GoalSegmentsView on the GPU, in the SwiftUI views' points. The pins, flag and car are small rasters drawn
// once per look (StingerCanvas.glShape) and then only moved; the fill, puff, blocks and every colour change are GPU work.
import CoreImage
import UIKit

extension GoalDraw {
    // MARK: Road trip

    /// GoalRoadView: "Road to: title" and amounts over a road with 25/50/75 % pins, a finish flag and the car at the fill.
    func road() -> GoalPiece {
        let title = run(input.celebrating ? input.title : "Road to: \(input.title)", 14, .bold, face: "Unbounded")
        let amount = run("", 14, .heavy)
        let tail = amount.with("/ " + input.targetText).colored(Self.dim)
        let ink = max(metrics(title).asc, metrics(amount).asc)
        let head = ink + max(metrics(title).height - metrics(title).asc, metrics(amount).height - metrics(amount).asc)
        let top = (74 - (head + 2 + 40)) / 2
        let spec = GoalFlip(before: input.beforeText, after: input.afterText, progress: GoalMotion.seg(prog, 0.5, 0.8))
        let amountRight = 478 - metrics(tail).width - 5
        let room = amountRight - flipWidth(spec, amount) - 8 - 8 - 18
        var layers: [CIImage] = []
        if style.background { layers.append(pill(area(0, 0, 500, 74), 16, style.backgroundColor)) }
        layers.append(contentsOf: [text(fit(title, width: room), x: 18, y: top + ink),
                                   flip(spec, amount, x: amountRight, y: top + ink, side: .trail),
                                   text(tail, x: 478, y: top + ink, side: .trail),
                                   moved(roadStrip(460), x: 18, y: top + head + 2)])
        return GoalPiece(image: pen.stack(layers), size: CGSize(width: 500, height: 74))
    }

    /// The 460 x 40 road in its own coordinates.
    private func roadStrip(_ wide: CGFloat) -> CIImage {
        let cx = wide * CGFloat(level(GoalMotion.move(prog)))
        let puff = prog < 0.2 ? prog / 0.2 * 0.7 : 0.7 * (1 - (prog - 0.2) / 0.8)
        let lane = pen.stack([fill(area(0, 26, wide, 9), style.trackColor), dashes(wide), fill(area(0, 26, cx, 9), accent)])
        var layers = [clipped(lane, to: area(0, 26, wide, 9))]
        layers.append(contentsOf: (0..<3).map { pin($0, wide) })
        layers.append(flag(wide - 12))
        let steam = CGPoint(x: cx - 36 - 22 * CGFloat(prog) + 4, y: 25 - 6 * CGFloat(prog) + 4)
        layers.append(disc(steam, 4 * (0.4 + CGFloat(prog)), Self.steel, alpha: CGFloat(puff)))
        layers.append(moved(car(), x: cx - 30, y: 13))
        return pen.stack(layers)
    }

    /// The centre line: 12 on, 12 off, white at 35 %.
    private func dashes(_ wide: CGFloat) -> CIImage {
        pen.stack(stride(from: CGFloat(0), to: wide, by: 24).map { fill(area($0, 30, min(12, wide - $0), 1), Self.white, alpha: 0.35) })
    }

    private func pin(_ index: Int, _ wide: CGFloat) -> CIImage {
        let mark = Double(index + 1) * 0.25
        let left = wide * CGFloat(mark) - 24
        let reached = input.to >= mark - 1e-9
        let label = run(index < input.pins.count ? input.pins[index] : "", 10, .semibold).colored(Self.dim).centred()
        let unit = self.unit
        let shape = pen.glShape("gl.pin|\(Int(unit * 100))", size: CGSize(width: 12 * unit, height: 16 * unit)) { ctx in
            ctx.scaleBy(x: unit * 12 / 22, y: unit * 16 / 30)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.move(to: CGPoint(x: 11, y: 29))
            ctx.addCurve(to: CGPoint(x: 21, y: 11), control1: CGPoint(x: 11, y: 29), control2: CGPoint(x: 21, y: 18))
            ctx.addCurve(to: CGPoint(x: 11, y: 1), control1: CGPoint(x: 21, y: 5.48), control2: CGPoint(x: 16.52, y: 1))
            ctx.addCurve(to: CGPoint(x: 1, y: 11), control1: CGPoint(x: 5.48, y: 1), control2: CGPoint(x: 1, y: 5.48))
            ctx.addCurve(to: CGPoint(x: 11, y: 29), control1: CGPoint(x: 1, y: 18), control2: CGPoint(x: 11, y: 29))
            ctx.fillPath()
        }
        let body = tinted(moved(shape, x: left + 18, y: 9), reached ? accent : 0xFF4A_4A4A)
        let hole = disc(CGPoint(x: left + 18 + 6, y: 9 + 5.87), 2.15, Self.ink)
        let name = text(fit(label, width: 48), x: left + 24, y: -3 + metrics(label).height / 2, side: .center)
        return pen.stack([name, body, hole])
    }

    /// The finish flag: a pole and a 2 x 2 chequered cloth (the lower squares are half height, like the board's).
    private func flag(_ left: CGFloat) -> CIImage {
        let cloth = (0..<4).map { square -> CIImage in
            let dark = (square / 2 + square % 2) % 2 == 0
            let cell = area(left + 4 + CGFloat(square % 2) * 6, 8 + CGFloat(square / 2) * 6, 6, square < 2 ? 6 : 3)
            return fill(cell, dark ? Self.ink : Self.white)
        }
        return pen.stack([pill(area(left + 2, 8, 2, 28), 1, Self.steel)] + cloth)
    }

    /// The board's car (64 x 36 viewBox at 36 x 20): accent shell, dark window, two wheels. Drawn once per accent.
    private func car() -> CIImage {
        let unit = self.unit
        let key = "gl.car|\(Int(unit * 100))|\(accent)"
        let color = accent
        return pen.glShape(key, size: CGSize(width: 36 * unit, height: 20 * unit)) { ctx in
            ctx.scaleBy(x: unit * 36 / 64, y: unit * 36 / 64)
            ctx.setFillColor(StingerArt.color(color))
            ctx.move(to: CGPoint(x: 6, y: 24))
            ctx.addLine(to: CGPoint(x: 8, y: 15))
            ctx.addQuadCurve(to: CGPoint(x: 15, y: 11), control: CGPoint(x: 10, y: 11))
            ctx.addLine(to: CGPoint(x: 23, y: 11))
            ctx.addLine(to: CGPoint(x: 30, y: 4))
            ctx.addQuadCurve(to: CGPoint(x: 36, y: 2), control: CGPoint(x: 32, y: 2))
            ctx.addLine(to: CGPoint(x: 46, y: 2))
            ctx.addQuadCurve(to: CGPoint(x: 52, y: 6), control: CGPoint(x: 50, y: 2))
            ctx.addLine(to: CGPoint(x: 56, y: 12))
            ctx.addQuadCurve(to: CGPoint(x: 62, y: 19), control: CGPoint(x: 62, y: 13))
            ctx.addLine(to: CGPoint(x: 62, y: 24))
            ctx.fillPath()
            ctx.setFillColor(StingerArt.color(Self.ink, alpha: 0.55))
            ctx.move(to: CGPoint(x: 30, y: 11))
            ctx.addLine(to: CGPoint(x: 35, y: 5))
            ctx.addLine(to: CGPoint(x: 45, y: 5))
            ctx.addLine(to: CGPoint(x: 49, y: 11))
            ctx.fillPath()
            for wheel: CGFloat in [10, 42] {
                ctx.setFillColor(StingerArt.color(Self.ink))
                ctx.fillEllipse(in: CGRect(x: wheel, y: 19, width: 14, height: 14))
                ctx.setFillColor(StingerArt.color(Self.steel))
                ctx.fillEllipse(in: CGRect(x: wheel + 4, y: 23, width: 6, height: 6))
            }
        }
    }

    // MARK: Segments

    /// GoalSegmentsView: TITLE, 20 blocks that flash white and settle to the accent, "total / target" and a floating "+delta".
    func segments() -> GoalPiece {
        let nb = min(20, max(0, Int((input.from * 20).rounded())))
        let na = min(20, max(nb, Int((input.to * 20).rounded())))
        let title = run(input.title.uppercased(), 13, .heavy, face: "JetBrainsMono").tracked(0.78).centred()
        let amount = run("", 13, .heavy, face: "JetBrainsMono").centred()
        let tail = run("/ " + input.targetText, 13, .medium, face: "JetBrainsMono").fading(0.7).centred()
        let spec = GoalFlip(before: input.beforeText, after: input.afterText, progress: GoalMotion.seg(prog, 0.4, 0.65))
        let amountW = flipWidth(spec, amount)
        let titleW = metrics(title).width
        let wide = 14 + titleW + 12 + 197 + 12 + amountW + 5 + metrics(tail).width + 14
        let blocks = 14 + titleW + 12
        let amountX = blocks + 197 + 12 + amountW
        let plus = GoalMotion.seg(prog, 0, 0.2) * (1 - GoalMotion.seg(prog, 0.6, 1))
        let delta = run(input.deltaText.isEmpty ? "" : "+" + input.deltaText, 12, .heavy, face: "JetBrainsMono").colored(accent)
        var layers: [CIImage] = []
        if style.background { layers.append(pill(area(0, 1, wide, 38), 12, style.backgroundColor)) }
        layers.append(contentsOf: [text(fit(title, width: 480 - (wide - titleW)), x: 14, y: 20),
                                   flip(spec, amount, x: amountX, y: 20, side: .trail),
                                   text(tail, x: amountX + 5, y: 20),
                                   text(delta.centred().fading(CGFloat(plus)), x: wide + 8, y: 28 - 18 * CGFloat(prog))])
        layers.append(contentsOf: (0..<20).map { block($0, nb, na, x: blocks + CGFloat($0) * 10) })
        return GoalPiece(image: pen.stack(layers), size: CGSize(width: 480, height: 40))
    }

    /// Blocks nb..<na are the new ones: flash white and grow, then settle to the accent, each a little after the last.
    private func block(_ index: Int, _ nb: Int, _ na: Int, x: CGFloat) -> CIImage {
        let isNew = index >= nb && index < na
        let late = prog - min(0.35, 0.05 * Double(index - nb))
        let flash = isNew ? GoalMotion.seg(late, 0.2, 0.35) : 0
        let settle = index < nb ? 1 : (isNew ? GoalMotion.seg(late, 0.35, 0.6) : 0)
        let grow = 1 + 0.6 * CGFloat(isNew ? flash - settle : 0)
        let cell = area(x, 12.5, 7, 15)
        let stack = pen.stack([pill(cell, 2, style.trackColor), pill(cell, 2, Self.white, alpha: CGFloat(flash)),
                               pill(cell, 2, accent, alpha: CGFloat(settle))])
        guard grow != 1 else { return stack }
        let centre = pt(x + 3.5, 20)
        return stack.transformed(by: CGAffineTransform(translationX: centre.x, y: centre.y).scaledBy(x: 1, y: grow)
            .translatedBy(x: -centre.x, y: -centre.y))
    }
}
