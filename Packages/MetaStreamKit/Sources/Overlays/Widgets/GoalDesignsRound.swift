// Minimal Goal designs built on rounds: Island pill (centred), Mini ring (leading) and Dot wave (leading). Sizes/colours/motion follow the
// Island / MiniRing / Dots boards; the reaction t 0...1 is the boards' donation window (loop 40...75 %), see GoalMotion.lp / kf.
// Content hugs its side of the fixed widget box and grows with the text (single-line titles and amounts).
// ponytail: no idle animation, everything moves with t only; t == 1 is the settled frame.
import SwiftUI
import UIKit

private func manrope(_ size: CGFloat, _ weight: UIFont.Weight) -> Font { WidgetFonts.font(face: "Manrope", size: size, weight: weight) }

/// Text width in points (for the pill's resting / expanded widths).
private func textWidth(_ s: String, _ size: CGFloat, _ weight: UIFont.Weight, _ track: CGFloat = 0) -> CGFloat {
    let f = WidgetFonts.uiFont(face: "Manrope", size: size, weight: weight)
    return ceil((s as NSString).size(withAttributes: [.font: f]).width + track * CGFloat(s.count))
}

// MARK: Island pill

struct GoalIslandView: View {
    let style: GoalWidgetStyle
    let title: String
    let beforeText: String
    let afterText: String
    let targetText: String
    let from: Double
    let to: Double
    let deltaText: String
    let t: Double

    private var amountW: CGFloat { max(textWidth(beforeText, 15, .heavy), textWidth(afterText, 15, .heavy)) }
    private var restW: CGFloat { 10 + 26 + 10 + amountW + textWidth(" / " + targetText, 15, .semibold) + 16 + 8 }
    private var burstW: CGFloat {
        let titleW: CGFloat = textWidth(title.uppercased(), 11, .semibold, 0.88)
        let line: CGFloat = textWidth(afterText, 17, .heavy) + textWidth(" / " + targetText, 14, .semibold)
        let plus: CGFloat = textWidth("+" + deltaText, 20, .heavy)
        let sum: CGFloat = 12 + 32 + 10 + max(titleW, line) + 16 + plus + 18 + 10
        return max(sum, restW + 60)
    }

    var body: some View {
        let rw = restW
        let bw = burstW
        let up = GoalMotion.seg(t, 0, 0.2)
        let u: Double = up - 1
        let u2: Double = u * u
        let back: Double = 1 + 2.2 * u2 * u + 1.2 * u2   // spring-like overshoot
        let e: Double = back * (1 - GoalMotion.smooth(GoalMotion.seg(t, 0.75, 1)))
        let w: CGFloat = rw + (bw - rw) * CGFloat(e)
        let h: CGFloat = 44 + 12 * CGFloat(e)
        let p: Double = from + (to - from) * GoalMotion.smooth(GoalMotion.seg(t, 0.12, 0.55))
        let restO: Double = min(1, (1 - GoalMotion.seg(t, 0, 0.08)) + GoalMotion.seg(t, 0.78, 0.9))
        let burstO: Double = GoalMotion.seg(t, 0.03, 0.18) * (1 - GoalMotion.seg(t, 0.7, 0.8))
        let glow: Double = GoalMotion.seg(t, 0, 0.12) * (1 - GoalMotion.seg(t, 0.12, 0.7))
        let accent = goalColor(style.barColor)
        ZStack(alignment: .leading) {
            rest(p, restO, w)
            burst(p, burstO, w)
        }
        .frame(width: w, height: h, alignment: .leading)
        .clipShape(Capsule())
        .background { if style.background { Capsule().fill(goalColor(style.backgroundColor)) } }
        .shadow(color: accent.opacity(0.8 * glow), radius: 14)
    }

    private func rest(_ p: Double, _ o: Double, _ w: CGFloat) -> some View {
        let text = goalColor(style.textColor)
        return HStack(spacing: 10) {
            ring(26, p)
            HStack(spacing: 0) {
                Text(t < 0.5 ? beforeText : afterText).frame(minWidth: amountW, alignment: .leading)
                Text(" / " + targetText).font(manrope(15, .semibold)).foregroundColor(text.opacity(0.55))
            }
            .font(manrope(15, .heavy)).monospacedDigit().lineLimit(1).fixedSize()
        }
        .foregroundColor(text)
        .padding(.leading, 10)
        .frame(width: w, alignment: .leading)
        .opacity(o)
    }

    private func burst(_ p: Double, _ o: Double, _ w: CGFloat) -> some View {
        let text = goalColor(style.textColor)
        let accent = goalColor(style.barColor)
        return HStack(spacing: 16) {
            HStack(spacing: 10) {
                ring(32, p)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.uppercased()).font(manrope(11, .semibold)).tracking(0.88).lineLimit(1)
                        .foregroundColor(text.opacity(0.65)).environment(\.layoutDirection, goalDir(title))
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(afterText).font(manrope(17, .heavy)).monospacedDigit()
                        Text(" / " + targetText).font(manrope(14, .semibold)).foregroundColor(text.opacity(0.55))
                    }
                    .lineLimit(1)
                }
            }
            .fixedSize()
            Spacer(minLength: 0)
            Text("+" + deltaText).font(manrope(20, .heavy)).foregroundColor(accent).lineLimit(1).fixedSize()
        }
        .foregroundColor(text)
        .padding(.leading, 12).padding(.trailing, 18)
        .frame(width: w, alignment: .leading)
        .scaleEffect(0.92 + 0.08 * GoalMotion.seg(t, 0.03, 0.18))
        .opacity(o)
    }

    /// The board's progress ring (26 viewBox, r 10, 3.5 stroke) at size d.
    private func ring(_ d: CGFloat, _ p: Double) -> some View {
        let k = d / 26
        return ZStack {
            Circle().stroke(goalColor(style.trackColor), lineWidth: 3.5 * k)
            Circle().trim(from: 0, to: CGFloat(min(1, max(0, p))))
                .stroke(goalColor(style.barColor), style: StrokeStyle(lineWidth: 3.5 * k, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(3 * k).frame(width: d, height: d)
    }
}

// MARK: Mini ring

struct GoalMiniRingView: View {
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
        let p: Double = from + (to - from) * GoalMotion.lp(t, 42, 60)
        let swap: Double = GoalMotion.lp(t, 56, 62)
        let plusO: Double = GoalMotion.kf(t, [(42, 0), (48, 1), (70, 1), (75, 0)])
        let plusY: CGFloat = CGFloat(GoalMotion.kf(t, [(42, 6), (48, 0), (70, 0), (75, -6)]))
        let text = goalColor(style.textColor)
        HStack(spacing: 14) {
            ringBlock(p, swap)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased()).font(manrope(11, .semibold)).tracking(1.54).lineLimit(1)
                    .foregroundColor(text.opacity(0.65)).environment(\.layoutDirection, goalDir(title))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    GoalSwap(before: beforeText, after: afterText, s: swap, alignment: .leading)
                        .font(manrope(18, .heavy)).monospacedDigit().frame(minWidth: 44, alignment: .leading)
                    Text("of \(targetText)").font(manrope(14, .semibold)).foregroundColor(text.opacity(0.55))
                }
                .lineLimit(1).fixedSize()
                Text(deltaText.isEmpty ? " " : "+\(deltaText) just now").font(manrope(12, .heavy)).lineLimit(1)
                    .foregroundColor(goalColor(style.barColor)).opacity(plusO).offset(y: plusY)
            }
        }
        .foregroundColor(text)
        .padding(.leading, 10).padding(.trailing, 18).padding(.vertical, 10)
        .background { if style.background { Capsule().fill(goalColor(style.backgroundColor)) } }
        .fixedSize()
    }

    private func ringBlock(_ p: Double, _ swap: Double) -> some View {
        let accent = goalColor(style.barColor)
        let pulseS: CGFloat = CGFloat(GoalMotion.kf(t, [(58, 0.9), (75, 1.45)]))
        let pulseO: Double = GoalMotion.kf(t, [(58, 0), (61, 0.8), (75, 0)])
        let cometO: Double = GoalMotion.kf(t, [(41, 0), (43, 1), (60, 1), (68, 0)])
        let ang: Double = 2 * Double.pi * p
        let cx: CGFloat = 30 * CGFloat(sin(ang))
        let cy: CGFloat = -30 * CGFloat(cos(ang))
        return ZStack {
            Circle().strokeBorder(accent, lineWidth: 2).scaleEffect(pulseS).opacity(pulseO)
            Circle().stroke(goalColor(style.trackColor), lineWidth: 5).padding(6)
            Circle().trim(from: 0, to: CGFloat(min(1, max(0, p))))
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(6)
            Circle().fill(Color.white).frame(width: 10, height: 10)   // comet: bright dot with glow, old to new angle
                .shadow(color: accent, radius: 5).shadow(color: accent, radius: 11)
                .offset(x: cx, y: cy).opacity(cometO)
            GoalSwap(before: goalPct(from), after: goalPct(to), s: swap, alignment: .center)
                .font(manrope(17, .heavy)).monospacedDigit().frame(minWidth: 40)
        }
        .frame(width: 72, height: 72)
    }
}

// MARK: Dot wave

struct GoalDotsView: View {
    let style: GoalWidgetStyle
    let title: String
    let beforeText: String
    let afterText: String
    let targetText: String
    let from: Double
    let to: Double
    let deltaText: String
    let t: Double

    private static let count = 24

    var body: some View {
        let n = Self.count
        let nb = min(n, max(0, Int((from * Double(n)).rounded())))
        let na = min(n, max(nb, Int((to * Double(n)).rounded())))
        let text = goalColor(style.textColor)
        let plusO: Double = GoalMotion.kf(t, [(48, 0), (54, 1), (66, 1), (75, 0)])
        let plusX: CGFloat = CGFloat(GoalMotion.kf(t, [(48, -6), (54, 0)]))
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(title.uppercased()).font(manrope(11, .semibold)).tracking(1.76).lineLimit(1)
                    .foregroundColor(text.opacity(0.65)).environment(\.layoutDirection, goalDir(title))
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    GoalSwap(before: beforeText, after: afterText, s: GoalMotion.lp(t, 52, 58))
                        .font(manrope(15, .heavy)).monospacedDigit().frame(minWidth: 40, alignment: .trailing)
                    Text("/ \(targetText)").font(manrope(13, .semibold)).foregroundColor(text.opacity(0.55))
                }
                .lineLimit(1).fixedSize()
                .overlay(alignment: .leading) {   // "+delta" floats out to the left of the amount, no layout of its own
                    Text(deltaText.isEmpty ? "" : "+" + deltaText).font(manrope(12, .heavy))
                        .foregroundColor(goalColor(style.barColor)).lineLimit(1).fixedSize()
                        .alignmentGuide(.leading) { $0[.trailing] + 8 }
                        .opacity(plusO).offset(x: plusX)
                }
            }
            .foregroundColor(text)
            HStack(spacing: 5) { ForEach(0..<n, id: \.self) { i in dot(i, nb, na) } }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background { if style.background { RoundedRectangle(cornerRadius: 14).fill(goalColor(style.backgroundColor)) } }
        .fixedSize()
    }

    /// Lit dots ripple (scale + brightness, each a little after the last); new dots pop white, then settle to the accent.
    private func dot(_ i: Int, _ nb: Int, _ na: Int) -> some View {
        let lit = i < nb
        let isNew = i >= nb && i < na
        let dw: Double = Double(i) * 0.58
        let nd: Double = Double(min(8, max(0, i - nb)))
        let wave: Double = lit ? GoalMotion.kf(t, [(40, 0), (44, 1), (50, 0)], delay: dw) : 0
        let pop: Double = isNew ? GoalMotion.kf(t, [(50, 1), (54, 1.9), (60, 1)], delay: nd) : 1
        let white: Double = isNew ? GoalMotion.kf(t, [(50, 0), (54, 1)], delay: nd) : 0
        let acc: Double = lit ? 1 : (isNew ? GoalMotion.kf(t, [(54, 0), (60, 1)], delay: nd) : 0)
        let sc: CGFloat = lit ? 1 + 0.7 * CGFloat(wave) : CGFloat(pop)
        return ZStack {
            Circle().fill(goalColor(style.trackColor))
            Circle().fill(Color.white).opacity(white)
            Circle().fill(goalColor(style.barColor)).opacity(acc)
        }
        .frame(width: 8, height: 8).scaleEffect(sc).brightness(0.3 * wave)
    }
}
