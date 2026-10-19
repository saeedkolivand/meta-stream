// Compact Goal designs: Liquid, Road trip, Segments (the minimal ones: GoalDesignsLine / GoalDesignsRound). Each draws one frame from (from -> to, reaction progress t).
// t is 0...1: 0 shows `from`/`beforeText`, 1 is settled and shows `to`/`afterText`. The render loop plays t over 1.6 s after a donation.
// ponytail: no idle animation (waves, bubbles, the car stay still between donations) so the widget costs nothing when
// nothing happens; the wave phase and bubbles only move with t.
import SwiftUI

func goalColor(_ argb: UInt32) -> Color { Color(uiColor: OverlayRaster.color(argb: argb)) }

extension Color {
    static let goalInk = Color(red: 18 / 255, green: 19 / 255, blue: 24 / 255)   // the boards' #121318
    static let goalSteel = Color(red: 0xD7 / 255, green: 0xD8 / 255, blue: 0xDE / 255)
    static let goalDim = Color(red: 0xA9 / 255, green: 0xAB / 255, blue: 0xB5 / 255)
}

enum GoalMotion {
    /// 0...1 progress of t inside the window a...b.
    static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }
    /// The move itself (fill, car) takes the first 75% of the reaction, eased.
    static func move(_ t: Double) -> Double { let s = seg(t, 0, 0.75); return s * s * (3 - 2 * s) }
    static func smooth(_ s: Double) -> Double { s * s * (3 - 2 * s) }
    /// The boards' 6 s loops put the donation at 40...75 % of the loop; `lp` is the eased progress of t inside loop-% window a...b.
    static func lp(_ t: Double, _ a: Double, _ b: Double) -> Double { smooth(seg(40 + 35 * t, a, b)) }
    /// Piecewise-linear board keyframes (loop %, value) sampled at t; `delay` shifts them later (loop %).
    static func kf(_ t: Double, _ pts: [(Double, Double)], delay: Double = 0) -> Double {
        let l = 40 + 35 * t - delay
        guard var prev = pts.first else { return 0 }
        if l <= prev.0 { return prev.1 }
        for p in pts.dropFirst() {
            if l <= p.0 { return prev.1 + (p.1 - prev.1) * (l - prev.0) / (p.0 - prev.0) }
            prev = p
        }
        return prev.1
    }
}

/// Old text fading out, new text rising in.
struct GoalSwap: View {
    let before: String
    let after: String
    let s: Double
    var alignment: Alignment = .trailing

    var body: some View {
        ZStack(alignment: alignment) {
            Text(before).opacity(1 - s)
            Text(after).opacity(s).offset(y: 8 * (1 - s))
        }
    }
}

func goalDir(_ text: String) -> LayoutDirection { WidgetFonts.isRTL(text) ? .rightToLeft : .leftToRight }

// MARK: Liquid

struct GoalLiquidView: View {
    let style: GoalWidgetStyle
    let title: String
    let beforeText: String
    let afterText: String
    let targetText: String
    let from: Double
    let to: Double
    let deltaText: String
    let t: Double

    var body: some View {
        let f = min(1, max(0, from + (to - from) * GoalMotion.move(t)))
        let swap = GoalMotion.seg(t, 0.2, 0.5)
        let text = goalColor(style.textColor)
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(WidgetFonts.font(face: "Unbounded", size: 17, weight: .bold)).lineLimit(1)
                    .environment(\.layoutDirection, goalDir(title))
                Spacer(minLength: 8)
                GoalSwap(before: beforeText, after: afterText, s: swap)
                Text("/ \(targetText)").foregroundColor(text.opacity(0.77))
            }
            .font(WidgetFonts.font(face: "Manrope", size: 17, weight: .heavy))
            .foregroundColor(text)
            tank(f, swap)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .frame(width: 420, height: 76, alignment: .center)
        .background { if style.background { RoundedRectangle(cornerRadius: 14).fill(goalColor(style.backgroundColor)) } }
    }

    private func tank(_ f: Double, _ swap: Double) -> some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let fw = w * CGFloat(f)
            let accent = goalColor(style.barColor)
            let phase = CGFloat((t * 64).truncatingRemainder(dividingBy: 64))
            let s = GoalMotion.seg(t, 0.1, 1)
            let splash = s < 0.17 ? s / 0.17 * 0.9 : 0.9 * (1 - (s - 0.17) / 0.83)
            ZStack(alignment: .topLeading) {
                Capsule().fill(goalColor(style.trackColor))
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(accent).frame(width: fw, height: h - 7).offset(y: 7)
                    wave(width: fw, phase: phase).fill(accent).frame(width: fw, height: 16)
                    wave(width: fw, phase: (96 - phase).truncatingRemainder(dividingBy: 64)).fill(Color.white.opacity(0.45))
                        .frame(width: fw, height: 16).offset(y: 2)
                    ForEach(0..<6, id: \.self) { i in bubble(i, fw, h) }
                }
                .frame(width: fw, height: h, alignment: .topLeading)
                .clipped()
                Circle().strokeBorder(Color.white, lineWidth: 2).frame(width: 28, height: 28)
                    .scaleEffect(CGFloat(0.4 + 1.2 * s)).opacity(splash).offset(x: fw - 14, y: 3)
                Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 2)
                if style.showPercent {
                    GoalSwap(before: "\(Int((from * 100).rounded()))%", after: "\(Int((to * 100).rounded()))%", s: swap)
                        .font(WidgetFonts.font(face: "Manrope", size: 14, weight: .heavy))
                        .foregroundColor(goalColor(style.textColor))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).padding(.trailing, 12)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 34)
    }

    /// Quadratic-curve crest 64 pt long, filled down to y = 16; `phase` slides it right.
    private func wave(width: CGFloat, phase: CGFloat) -> Path {
        Path { p in
            let x0 = -64 + phase
            var x = x0
            var up = true
            p.move(to: CGPoint(x: x, y: 8))
            while x < width {
                p.addQuadCurve(to: CGPoint(x: x + 32, y: 8), control: CGPoint(x: x + 16, y: up ? 0 : 16))
                x += 32
                up.toggle()
            }
            p.addLine(to: CGPoint(x: x, y: 16))
            p.addLine(to: CGPoint(x: x0, y: 16))
            p.closeSubpath()
        }
    }

    private func bubble(_ i: Int, _ fw: CGFloat, _ h: CGFloat) -> some View {
        let u: Double = (t * 0.9 + Double(i) * 0.17).truncatingRemainder(dividingBy: 1)
        let o: Double = u < 0.2 ? u / 0.2 * 0.8 : 0.8 * (1 - u) / 0.8
        let scale: CGFloat = 0.6 + 0.4 * CGFloat(u)
        let x: CGFloat = fw * CGFloat(0.1 + 0.16 * Double(i)) - 3
        let y: CGFloat = h - 9 - 30 * CGFloat(u)
        return Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5).frame(width: 6, height: 6)
            .scaleEffect(scale).opacity(o)
            .offset(x: x, y: y)
    }
}

// MARK: Road trip

struct GoalRoadView: View {
    let style: GoalWidgetStyle
    let title: String
    let beforeText: String
    let afterText: String
    let targetText: String
    let from: Double
    let to: Double
    let deltaText: String
    let t: Double
    var pins: [String] = []          // amounts at 25 / 50 / 75 %
    var celebrating = false          // the title then is the celebration text, no "Road to:" prefix

    var body: some View {
        let f = min(1, max(0, from + (to - from) * GoalMotion.move(t)))
        let swap = GoalMotion.seg(t, 0.5, 0.8)
        let text = goalColor(style.textColor)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(celebrating ? title : "Road to: \(title)").font(WidgetFonts.font(face: "Unbounded", size: 14, weight: .bold))
                    .lineLimit(1).environment(\.layoutDirection, goalDir(title))
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    GoalSwap(before: beforeText, after: afterText, s: swap)
                    Text("/ \(targetText)").foregroundColor(Color.goalDim)
                }
                .font(WidgetFonts.font(face: "Manrope", size: 14, weight: .heavy))
            }
            .foregroundColor(text)
            GeometryReader { g in road(g.size.width, f) }.frame(height: 40)
        }
        .padding(.leading, 18).padding(.trailing, 22).padding(.vertical, 7)
        .frame(width: 500, height: 74, alignment: .center)
        .background { if style.background { RoundedRectangle(cornerRadius: 16).fill(goalColor(style.backgroundColor)) } }
    }

    private func road(_ w: CGFloat, _ f: Double) -> some View {
        let accent = goalColor(style.barColor)
        let cx = w * CGFloat(f)
        let puff = t < 0.2 ? t / 0.2 * 0.7 : 0.7 * (1 - (t - 0.2) / 0.8)
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(goalColor(style.trackColor))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0.5))
                    p.addLine(to: CGPoint(x: w, y: 0.5))
                }
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [12, 12]))
                .frame(width: w, height: 1).offset(y: 4)
                Rectangle().fill(accent).frame(width: cx, height: 9)
            }
            .frame(width: w, height: 9)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .offset(y: 26)
            ForEach(0..<3, id: \.self) { i in pinView(i, w, accent) }
            flag.offset(x: w - 12, y: 8)
            Circle().fill(Color.goalSteel).frame(width: 8, height: 8).scaleEffect(CGFloat(0.4 + t)).opacity(puff)
                .offset(x: cx - 36 - 22 * CGFloat(t), y: 25 - 6 * CGFloat(t) as CGFloat)
            car(accent).offset(x: cx - 30, y: 13)
        }
    }

    private func pinView(_ i: Int, _ w: CGFloat, _ accent: Color) -> some View {
        let m = Double(i + 1) * 0.25
        return ZStack(alignment: .topLeading) {
            Text(i < pins.count ? pins[i] : "")
                .font(WidgetFonts.font(face: "Manrope", size: 10, weight: .semibold))
                .foregroundColor(Color.goalDim).lineLimit(1).frame(width: 48).offset(y: -3)
            ZStack(alignment: .topLeading) {
                Self.pinPath.fill(to >= m - 1e-9 ? accent : Color(white: 0.29))
                Circle().fill(Color.goalInk).frame(width: 4.3, height: 4.3).offset(x: 3.85, y: 3.72)
            }
            .frame(width: 12, height: 16, alignment: .topLeading).offset(x: 18, y: 9)
        }
        .frame(width: 48, height: 40, alignment: .topLeading)
        .offset(x: w * CGFloat(m) - 24)
    }

    /// The board's map-pin (22x30 viewBox) at 12x16.
    private static var pinPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 11, y: 29))
        p.addCurve(to: CGPoint(x: 21, y: 11), control1: CGPoint(x: 11, y: 29), control2: CGPoint(x: 21, y: 18))
        p.addCurve(to: CGPoint(x: 11, y: 1), control1: CGPoint(x: 21, y: 5.48), control2: CGPoint(x: 16.52, y: 1))
        p.addCurve(to: CGPoint(x: 1, y: 11), control1: CGPoint(x: 5.48, y: 1), control2: CGPoint(x: 1, y: 5.48))
        p.addCurve(to: CGPoint(x: 11, y: 29), control1: CGPoint(x: 1, y: 18), control2: CGPoint(x: 11, y: 29))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: 12.0 / 22, y: 16.0 / 30))
    }

    private var flag: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1).fill(Color.goalSteel).frame(width: 2, height: 28).offset(x: 2)
            ForEach(0..<4, id: \.self) { k in
                Rectangle().fill((k / 2 + k % 2) % 2 == 0 ? Color.goalInk : Color.white)
                    .frame(width: 6, height: k < 2 ? 6 : 3).offset(x: 4 + CGFloat(k % 2) * 6, y: CGFloat(k / 2) * 6)
            }
        }
        .frame(width: 16, height: 30, alignment: .topLeading)
    }

    /// The board's car (64x36 viewBox) at 36x20.
    private func car(_ accent: Color) -> some View {
        let s = CGAffineTransform(scaleX: 36.0 / 64, y: 36.0 / 64)
        var shell = Path()
        shell.move(to: CGPoint(x: 6, y: 24))
        shell.addLine(to: CGPoint(x: 8, y: 15))
        shell.addQuadCurve(to: CGPoint(x: 15, y: 11), control: CGPoint(x: 10, y: 11))
        shell.addLine(to: CGPoint(x: 23, y: 11))
        shell.addLine(to: CGPoint(x: 30, y: 4))
        shell.addQuadCurve(to: CGPoint(x: 36, y: 2), control: CGPoint(x: 32, y: 2))
        shell.addLine(to: CGPoint(x: 46, y: 2))
        shell.addQuadCurve(to: CGPoint(x: 52, y: 6), control: CGPoint(x: 50, y: 2))
        shell.addLine(to: CGPoint(x: 56, y: 12))
        shell.addQuadCurve(to: CGPoint(x: 62, y: 19), control: CGPoint(x: 62, y: 13))
        shell.addLine(to: CGPoint(x: 62, y: 24))
        shell.closeSubpath()
        var window = Path()
        window.move(to: CGPoint(x: 30, y: 11))
        window.addLine(to: CGPoint(x: 35, y: 5))
        window.addLine(to: CGPoint(x: 45, y: 5))
        window.addLine(to: CGPoint(x: 49, y: 11))
        window.closeSubpath()
        return ZStack(alignment: .topLeading) {
            shell.applying(s).fill(accent)
            window.applying(s).fill(Color.goalInk.opacity(0.55))
            Path(ellipseIn: CGRect(x: 10, y: 19, width: 14, height: 14)).applying(s).fill(Color.goalInk)
            Path(ellipseIn: CGRect(x: 14, y: 23, width: 6, height: 6)).applying(s).fill(Color.goalSteel)
            Path(ellipseIn: CGRect(x: 42, y: 19, width: 14, height: 14)).applying(s).fill(Color.goalInk)
            Path(ellipseIn: CGRect(x: 46, y: 23, width: 6, height: 6)).applying(s).fill(Color.goalSteel)
        }
        .frame(width: 36, height: 20, alignment: .topLeading)
    }
}

// MARK: Segments

struct GoalSegmentsView: View {
    let style: GoalWidgetStyle
    let title: String
    let beforeText: String
    let afterText: String
    let targetText: String
    let from: Double
    let to: Double
    let deltaText: String
    let t: Double

    var body: some View {
        let nb = min(20, max(0, Int((from * 20).rounded())))
        let na = min(20, max(nb, Int((to * 20).rounded())))
        let accent = goalColor(style.barColor)
        let text = goalColor(style.textColor)
        let plus = GoalMotion.seg(t, 0, 0.2) * (1 - GoalMotion.seg(t, 0.6, 1))
        HStack(spacing: 12) {
            Text(title.uppercased()).font(WidgetFonts.font(face: "JetBrainsMono", size: 13, weight: .heavy)).tracking(0.78)
                .lineLimit(1).environment(\.layoutDirection, goalDir(title))
            HStack(spacing: 3) { ForEach(0..<20, id: \.self) { i in block(i, nb, na) } }.frame(height: 20)
            HStack(spacing: 5) {
                GoalSwap(before: beforeText, after: afterText, s: GoalMotion.seg(t, 0.4, 0.65))
                Text("/ \(targetText)").font(WidgetFonts.font(face: "JetBrainsMono", size: 13, weight: .medium)).foregroundColor(text.opacity(0.7))
            }
            .font(WidgetFonts.font(face: "JetBrainsMono", size: 13, weight: .heavy))
        }
        .foregroundColor(text)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background { if style.background { RoundedRectangle(cornerRadius: 12).fill(goalColor(style.backgroundColor)) } }
        .overlay(alignment: .trailing) {
            Text(deltaText.isEmpty ? "" : "+" + deltaText)
                .font(WidgetFonts.font(face: "JetBrainsMono", size: 12, weight: .heavy)).foregroundColor(accent)
                .opacity(plus).offset(y: 8 - 18 * CGFloat(t))
                .alignmentGuide(.trailing) { $0[.leading] - 8 }
        }
        .frame(width: 480, height: 40, alignment: .leading)
    }

    /// Blocks nb..<na are the new ones: flash white and grow, then settle to the accent, each a little after the last.
    private func block(_ i: Int, _ nb: Int, _ na: Int) -> some View {
        let isNew = i >= nb && i < na
        let u = t - min(0.35, 0.05 * Double(i - nb))
        let a = isNew ? GoalMotion.seg(u, 0.2, 0.35) : 0
        let b = i < nb ? 1 : (isNew ? GoalMotion.seg(u, 0.35, 0.6) : 0)
        return ZStack {
            Rectangle().fill(goalColor(style.trackColor))
            Rectangle().fill(Color.white).opacity(a)
            Rectangle().fill(goalColor(style.barColor)).opacity(b)
        }
        .frame(width: 7, height: 15)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .scaleEffect(x: 1, y: 1 + 0.6 * CGFloat(isNew ? a - b : 0))
    }
}

// MARK: dispatch

/// The chosen non-bar design (`style.design`: "liquid", "road", "segments", "hairline", "island", "miniring", "dots", "spark").
struct GoalDesignView: View {
    let style: GoalWidgetStyle
    let title: String
    let beforeText: String
    let afterText: String
    let targetText: String
    let from: Double
    let to: Double
    let deltaText: String
    let t: Double
    var pins: [String] = []
    var celebrating = false

    /// The designs are laid out in 1280-wide board units (the previews); a stream canvas is 1920 wide, so draw 1.5x.
    static let scale: CGFloat = 1.5

    var body: some View {
        // The box is fixed; variable-width designs hug one side of it (laid out in board units, then scaled).
        let box = style.natural
        design.frame(width: box.width / Self.scale, height: box.height / Self.scale, alignment: Self.side(style.design))
            .scaleEffect(Self.scale, anchor: .topLeading)
            .frame(width: box.width, height: box.height, alignment: .topLeading)
    }

    static func side(_ design: String) -> Alignment { design == "spark" ? .trailing : design == "island" ? .center : .leading }
    /// How long the donation reaction plays (the island pill expands, holds and contracts).
    static func reactionSeconds(_ design: String) -> Double { design == "island" ? 2.4 : 1.6 }

    @ViewBuilder private var design: some View {
        switch style.design {
        case "road":
            GoalRoadView(style: style, title: title, beforeText: beforeText, afterText: afterText, targetText: targetText,
                         from: from, to: to, deltaText: deltaText, t: t, pins: pins, celebrating: celebrating)
        case "segments":
            GoalSegmentsView(style: style, title: title, beforeText: beforeText, afterText: afterText, targetText: targetText,
                             from: from, to: to, deltaText: deltaText, t: t)
        case "hairline":
            GoalHairlineView(style: style, title: title, beforeText: beforeText, afterText: afterText, targetText: targetText,
                             from: from, to: to, deltaText: deltaText, t: t)
        case "island":
            GoalIslandView(style: style, title: title, beforeText: beforeText, afterText: afterText, targetText: targetText,
                           from: from, to: to, deltaText: deltaText, t: t)
        case "miniring":
            GoalMiniRingView(style: style, title: title, beforeText: beforeText, afterText: afterText, targetText: targetText,
                             from: from, to: to, deltaText: deltaText, t: t)
        case "dots":
            GoalDotsView(style: style, title: title, beforeText: beforeText, afterText: afterText, targetText: targetText,
                         from: from, to: to, deltaText: deltaText, t: t)
        case "spark":
            GoalSparkView(style: style, title: title, beforeText: beforeText, afterText: afterText, targetText: targetText,
                          from: from, to: to, deltaText: deltaText, t: t)
        default:
            GoalLiquidView(style: style, title: title, beforeText: beforeText, afterText: afterText, targetText: targetText,
                           from: from, to: to, deltaText: deltaText, t: t)
        }
    }

    /// Settled sample for the layer preview.
    static func sample(_ style: GoalWidgetStyle) -> GoalDesignView {
        GoalDesignView(style: style, title: "New camera", beforeText: "€312", afterText: "€312", targetText: "€800",
                       from: 0.39, to: 0.39, deltaText: "", t: 1, pins: ["€200", "€400", "€600"])
    }
}
