// Minimal Goal designs drawn as a line: Hairline (leading) and Spark (trailing). Sizes/colours/motion follow the Hairline / Spark boards;
// the reaction t 0...1 is the boards' donation window (loop 40...75 %), see GoalMotion.lp / kf. Titles and amounts never wrap: the content
// hugs one side of the fixed widget box and grows with the text.
// ponytail: no idle animation, everything moves with t only; t == 1 is the settled frame.
import SwiftUI

func goalPct(_ v: Double) -> String { "\(Int((min(1, max(0, v)) * 100).rounded()))%" }

/// Old text sliding up and out while the new one rolls in from below (clipped to `h`).
struct GoalRoll: View {
    let before: String
    let after: String
    let s: Double
    let h: CGFloat
    var alignment: Alignment = .leading

    var body: some View {
        let k = CGFloat(s)
        ZStack(alignment: alignment) {
            Text(before).lineLimit(1).fixedSize().opacity(1 - s).offset(y: -h * k)
            Text(after).lineLimit(1).fixedSize().opacity(s).offset(y: h * (1 - k))
        }
        .frame(height: h).clipped()
    }
}

// MARK: Hairline

struct GoalHairlineView: View {
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
        let f: Double = min(1, max(0, from + (to - from) * GoalMotion.lp(t, 40, 56)))
        let roll: Double = GoalMotion.lp(t, 44, 52)
        let text = goalColor(style.textColor)
        let head = WidgetFonts.font(face: "Manrope", size: 11, weight: .bold)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text(title.uppercased()).font(head).tracking(2.2).lineLimit(1)
                    .environment(\.layoutDirection, goalDir(title))
                Spacer(minLength: 0)
                if style.showPercent {
                    GoalRoll(before: goalPct(from), after: goalPct(to), s: roll, h: 14, alignment: .trailing)
                        .font(head).tracking(2.2).frame(minWidth: 34, alignment: .trailing)
                }
            }
            .foregroundColor(text.opacity(0.72))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                GoalRoll(before: beforeText, after: afterText, s: roll, h: 38)
                    .font(WidgetFonts.font(face: "Manrope", size: 32, weight: .heavy)).monospacedDigit()
                    .frame(minWidth: 96, alignment: .leading)
                Text("of \(targetText)").font(WidgetFonts.font(face: "Manrope", size: 14, weight: .semibold))
                    .foregroundColor(text.opacity(0.6)).lineLimit(1)
            }
            .foregroundColor(text)
            bar(f)
        }
        .shadow(color: Color.black.opacity(0.55), radius: 3, y: 1)
        .frame(minWidth: 340, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background { if style.background { RoundedRectangle(cornerRadius: 12).fill(goalColor(style.backgroundColor)) } }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func bar(_ f: Double) -> some View {
        let accent = goalColor(style.barColor)
        return Color.white.opacity(0.14).frame(height: 2).frame(maxWidth: .infinity)
            .overlay { GeometryReader { g in fill(g.size.width * CGFloat(f), accent) } }
    }

    private func fill(_ fw: CGFloat, _ accent: Color) -> some View {
        let sweepX: CGFloat = CGFloat(GoalMotion.kf(t, [(42, -0.3), (64, 1.05)])) * fw
        let sweepO: Double = GoalMotion.kf(t, [(42, 0), (46, 1), (64, 0)])
        let tip: CGFloat = CGFloat(GoalMotion.kf(t, [(40, 1), (48, 1.8), (66, 1)]))
        let glow: CGFloat = CGFloat(GoalMotion.kf(t, [(40, 0), (48, 8), (66, 3)]))
        let ghostO: Double = GoalMotion.kf(t, [(42, 0), (48, 1), (70, 0)])
        let ghostY: CGFloat = CGFloat(GoalMotion.kf(t, [(42, 4), (48, -6), (70, -22)]))
        let white = LinearGradient(colors: [Color.white.opacity(0), Color.white, Color.white.opacity(0)], startPoint: .leading, endPoint: .trailing)
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                accent
                white.frame(width: 60).offset(x: sweepX).opacity(sweepO)   // white sweep along the fill
            }
            .frame(width: fw, height: 2, alignment: .topLeading).clipShape(Capsule())
            Circle().fill(Color.white).frame(width: 6, height: 6).scaleEffect(tip)
                .shadow(color: accent, radius: glow).offset(x: fw - 3, y: -2)
            Text(deltaText.isEmpty ? "" : "+" + deltaText)
                .font(WidgetFonts.font(face: "Manrope", size: 13, weight: .heavy)).foregroundColor(accent)
                .lineLimit(1).fixedSize().frame(width: 0, alignment: .trailing)   // right edge at the offset
                .opacity(ghostO).offset(x: fw + 18, y: -22 + ghostY)
        }
    }
}

// MARK: Spark

struct GoalSparkView: View {
    let style: GoalWidgetStyle
    let title: String
    let beforeText: String
    let afterText: String
    let targetText: String
    let from: Double
    let to: Double
    let deltaText: String
    let t: Double

    /// The board's 9 particle targets (x, y), up and back from the tip.
    private static let bits: [(CGFloat, CGFloat)] = [(-26, -22), (-40, -8), (-18, -34), (-48, -26), (-10, -18),
                                                     (-34, 6), (-22, 12), (-56, -4), (-6, -40)]

    var body: some View {
        let f: Double = min(1, max(0, from + (to - from) * GoalMotion.lp(t, 40, 52)))
        let text = goalColor(style.textColor)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text(title).font(WidgetFonts.font(face: "Manrope", size: 13, weight: .heavy)).lineLimit(1)
                    .environment(\.layoutDirection, goalDir(title))
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    GoalSwap(before: beforeText, after: afterText, s: GoalMotion.lp(t, 50, 56))
                        .font(WidgetFonts.font(face: "Manrope", size: 15, weight: .heavy)).monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                    Text("/ \(targetText)").font(WidgetFonts.font(face: "Manrope", size: 13, weight: .semibold))
                        .foregroundColor(text.opacity(0.6))
                }
                .lineLimit(1).fixedSize()
            }
            .foregroundColor(text)
            bar(f)
        }
        .shadow(color: Color.black.opacity(0.55), radius: 3, y: 1)
        .frame(minWidth: 380, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background { if style.background { RoundedRectangle(cornerRadius: 12).fill(goalColor(style.backgroundColor)) } }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func bar(_ f: Double) -> some View {
        let accent = goalColor(style.barColor)
        return Color.white.opacity(0.12).frame(height: 4).frame(maxWidth: .infinity).clipShape(Capsule())
            .overlay { GeometryReader { g in fill(g.size.width * CGFloat(f), accent) } }
    }

    private func fill(_ fw: CGFloat, _ accent: Color) -> some View {
        let flash: Double = GoalMotion.kf(t, [(40, 0), (50, 1), (66, 0)])
        let core: CGFloat = CGFloat(GoalMotion.kf(t, [(40, 1), (52, 1.9), (70, 1)]))
        let coreGlow: CGFloat = CGFloat(GoalMotion.kf(t, [(40, 5), (52, 12), (70, 5)]))
        return ZStack(alignment: .topLeading) {
            Capsule().fill(accent).frame(width: fw, height: 4).brightness(0.3 * flash)
            Circle().fill(Color.white).frame(width: 10, height: 10).scaleEffect(core)
                .shadow(color: accent, radius: coreGlow).offset(x: fw - 5, y: -3)
            ForEach(0..<Self.bits.count, id: \.self) { i in bit(i, fw, accent) }
        }
    }

    /// Particle i: appears at the tip, flies out (eased) and shrinks away, each 0.33 loop-% after the last.
    private func bit(_ i: Int, _ fw: CGFloat, _ accent: Color) -> some View {
        let d: Double = Double(i) * 0.33
        let o: Double = GoalMotion.kf(t, [(50, 0), (52, 1), (72, 0)], delay: d)
        let lin: Double = GoalMotion.kf(t, [(50, 0), (72, 1)], delay: d)
        let k: CGFloat = CGFloat(1 - (1 - lin) * (1 - lin))
        let target = Self.bits[i]
        let sc: CGFloat = 1 - 0.7 * CGFloat(lin)
        return Circle().fill(Color.white).frame(width: 4, height: 4).shadow(color: accent, radius: 3)
            .scaleEffect(sc).opacity(o)
            .offset(x: fw - 2 + target.0 * k, y: target.1 * k)
    }
}
