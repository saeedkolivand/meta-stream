// Donation alerts drawn live on the GPU, like the stingers (designs: the "Donation Alerts" canvas,
// https://claude.ai/artifact/F1Da3KuHjD9KrHYr4cCpkq). Every frame is a pure function of `p`, the alert's progress
// 0...1, so each recipe reads like the board's CSS keyframes (percent of the loop). Recipes draw in top-left
// canvas coordinates on a StingerCanvas; the screen object flips the finished picture once.
import CoreGraphics
import CoreImage

enum DonationAlertKind: String, CaseIterable, Sendable {
    case island, coinBurst, neon, receipt, holo, shockwave, goalSurge

    var title: String {
        switch self {
        case .island: "Island"
        case .coinBurst: "Coin burst"
        case .neon: "Neon sign"
        case .receipt: "Receipt"
        case .holo: "Holo card"
        case .shockwave: "Shockwave"
        case .goalSurge: "Goal surge"
        }
    }

    /// Length at Normal speed: the board's loop (Slow and Quick scale it, see DonationAlertStyle.speed).
    var seconds: Double {
        switch self {
        case .island: 0   // the existing banner, played by AlertPlayer
        case .coinBurst, .neon, .goalSurge: 6
        case .receipt, .holo, .shockwave: 7
        }
    }
}

/// What a donation alert shows; built once when the alert starts.
struct DonationAlertInfo: Sendable {
    var name: String            // display name, already cleaned
    var initial: String         // first letter of the name, for the avatar disc
    var amount: String          // in the currency it was given in: "₮1,500,000", "€25", "500 KICKs"
    var message: String         // may be Persian (lay it out right-to-left) or empty
    var source: String          // "DONOFA", "KICK", "TWITCH", "YOUTUBE", ...
    var rate: String            // "₮59,000/€", "1:1", or "" when unknown (receipt)
    var toGoal: String          // what it added to the goal, "€25.42", or "" without a goal
    var tier: Int               // 0 rare, 1 epic, 2 legendary (holo card): under $10, under $50, $50 and up
    var date: String            // "18 OCT 2026" (receipt)
    var time: String            // "21:42"
    var goal: Goal?             // goal surge; nil = no goal set

    struct Goal: Sendable {
        var title: String       // "New camera"
        var before: String      // "€312"
        var after: String       // "€337"
        var target: String      // "€800"
        var from: Double        // progress before, 0...1
        var to: Double          // progress after
        var box: CGRect?        // the scene's Goal widget on the canvas (top-left coords); nil = draw at top centre
    }
}

struct DonationAlertStyle: Equatable, Sendable {
    var accent: UInt32 = 0          // 0 = the design's own colour (the board's default)
    var second: UInt32 = 0          // neon's second tube; 0 = board default
    var speed: Double = 1           // 0.75 slow, 1 normal, 1.33 quick: duration = seconds / speed
}

/// The 1280x720 board laid onto the canvas: scaled to fit the width or height, centred horizontally, top-aligned.
/// ponytail: on a portrait canvas the board shrinks to the width; a portrait layout per design if that reads small.
struct DonationBoard {
    let s: CGFloat
    let origin: CGPoint

    init(_ canvas: CGSize) {
        s = min(canvas.width / 1280, canvas.height / 720)
        origin = CGPoint(x: (canvas.width - 1280 * s) / 2, y: 0)
    }

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * s, y: origin.y + y * s) }
    func len(_ v: CGFloat) -> CGFloat { v * s }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: origin.x + x * s, y: origin.y + y * s, width: w * s, height: h * s) }
}

/// Keyframe helpers shared by the recipes: percent-of-loop windows like the CSS boards.
enum Key {
    /// 0 before `a`, 1 after `b`, linear between (a, b in 0...1).
    static func span(_ p: Double, _ a: Double, _ b: Double) -> Double { b <= a ? (p >= b ? 1 : 0) : min(1, max(0, (p - a) / (b - a))) }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
    static func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    static func easeIn(_ t: Double) -> Double { t * t * t }
    static func easeInOut(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
    /// Overshoots past 1 then settles (the boards' cubic-bezier(.2,.9,.25,1.15) pops).
    static func back(_ t: Double, _ k: Double = 1.7) -> Double { let u = t - 1; return 1 + (k + 1) * u * u * u + k * u * u }
}

enum DonationArt {
    static func frame(_ k: DonationAlertKind, p: Double, info: DonationAlertInfo, style: DonationAlertStyle, c: StingerCanvas) -> CIImage {
        let b = DonationBoard(c.size)
        switch k {
        case .island: return .empty()
        case .coinBurst: return coinBurst(p: p, info: info, style: style, c: c, b: b)
        case .neon: return neon(p: p, info: info, style: style, c: c, b: b)
        case .receipt: return receipt(p: p, info: info, style: style, c: c, b: b)
        case .holo: return holo(p: p, info: info, style: style, c: c, b: b)
        case .shockwave: return shockwave(p: p, info: info, style: style, c: c, b: b)
        case .goalSurge: return goalSurge(p: p, info: info, style: style, c: c, b: b)
        }
    }
}
