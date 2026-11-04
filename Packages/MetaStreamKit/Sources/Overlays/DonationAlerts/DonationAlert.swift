// Donation alerts drawn live on the GPU, like the stingers (designs: the "Donation Alerts" canvas,
// https://claude.ai/artifact/F1Da3KuHjD9KrHYr4cCpkq). Every frame is a pure function of `p`, the alert's progress
// 0...1, so each recipe reads like the board's CSS keyframes (percent of the loop). Recipes draw in top-left
// canvas coordinates on a StingerCanvas; the screen object flips the finished picture once.
import CoreGraphics
import CoreImage

public enum DonationAlertKind: String, CaseIterable, Sendable {
    case island, coinBurst, neon, receipt, holo, shockwave, goalSurge

    public var title: String {
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

    /// The design's main element on the 1280x720 board: this is what sits on the Alerts widget's box.
    public var focus: CGRect {
        switch self {
        case .island: CGRect(x: 0, y: 0, width: 1280, height: 720)
        case .coinBurst: CGRect(x: 240, y: 60, width: 800, height: 200)
        case .neon: CGRect(x: 300, y: 80, width: 680, height: 340)
        case .receipt: CGRect(x: 820, y: 38, width: 380, height: 682)
        case .holo: CGRect(x: 120, y: 100, width: 360, height: 510)
        case .shockwave: CGRect(x: 240, y: 100, width: 800, height: 380)
        case .goalSurge: CGRect(x: 80, y: 560, width: 300, height: 80)
        }
    }

    /// Length at Normal speed: the board's loop (Slow and Quick scale it, see DonationAlertStyle.speed).
    public var seconds: Double {
        switch self {
        case .island: 0   // the existing banner, played by AlertPlayer
        case .coinBurst, .neon, .goalSurge: 6
        case .receipt, .holo, .shockwave: 7
        }
    }
}

/// What a donation alert shows; built once when the alert starts.
public struct DonationAlertInfo: Sendable {
    public var name: String            // display name, already cleaned
    public var initial: String         // first letter of the name, for the avatar disc
    public var amount: String          // in the currency it was given in: "₮1,500,000", "€25", "500 KICKs"
    public var message: String         // may be Persian (lay it out right-to-left) or empty
    public var source: String          // "DONOFA", "KICK", "TWITCH", "YOUTUBE", ...
    public var rate: String            // "₮59,000/€", "1:1", or "" when unknown (receipt)
    public var toGoal: String          // what it added to the goal, "€25.42", or "" without a goal
    public var tier: Int               // 0 rare, 1 epic, 2 legendary (holo card): under $10, under $50, $50 and up
    public var date: String            // "18 OCT 2026" (receipt)
    public var time: String            // "21:42"
    public var goal: Goal?             // goal surge; nil = no goal set

    public struct Goal: Sendable {
        public var title: String       // "New camera"
        public var before: String      // "€312"
        public var after: String       // "€337"
        public var target: String      // "€800"
        public var from: Double        // progress before, 0...1
        public var to: Double          // progress after
        public var box: CGRect?        // the scene's Goal widget on the canvas (top-left coords); nil = draw at top centre

        public init(title: String, before: String, after: String, target: String, from: Double, to: Double, box: CGRect? = nil) {
            (self.title, self.before, self.after, self.target) = (title, before, after, target)
            (self.from, self.to, self.box) = (from, to, box)
        }
    }

    public init(name: String, initial: String, amount: String, message: String, source: String, rate: String, toGoal: String,
                tier: Int, date: String, time: String, goal: Goal? = nil) {
        (self.name, self.initial, self.amount, self.message, self.source) = (name, initial, amount, message, source)
        (self.rate, self.toGoal, self.tier, self.date, self.time, self.goal) = (rate, toGoal, tier, date, time, goal)
    }
}

public struct DonationAlertStyle: Equatable, Sendable {
    public var accent: UInt32 = 0          // 0 = the design's own colour (the board's default)
    public var second: UInt32 = 0          // neon's second tube; 0 = board default
    public var speed: Double = 1           // 0.75 slow, 1 normal, 1.33 quick: duration = seconds / speed
}

/// The 1280x720 board laid onto the canvas: scaled to fit the width or height, centred horizontally, top-aligned.
/// ponytail: on a portrait canvas the board shrinks to the width; a portrait layout per design if that reads small.
public struct DonationBoard {
    public let s: CGFloat
    public let origin: CGPoint

    public init(_ canvas: CGSize) {
        s = min(canvas.width / 1280, canvas.height / 720)
        origin = CGPoint(x: (canvas.width - 1280 * s) / 2, y: 0)
    }

    /// Follows the Alerts widget: `box` is its rect on the canvas. The scale is the fit scale times the widget's layer scale
    /// (box.width / its width at layer scale 1, which is 900 * min(canvas) / 1080), and the design's `focus` rect (board
    /// coords) is centred on the box, kept inside the canvas. nil box = the plain layout above.
    public init(_ canvas: CGSize, focus: CGRect, box: CGRect?) {
        let base = min(canvas.width / 1280, canvas.height / 720)
        guard let box, box.width > 0 else {
            s = base
            origin = CGPoint(x: (canvas.width - 1280 * base) / 2, y: 0)
            return
        }
        let unit = 900 * min(canvas.width, canvas.height) / 1080
        let sc = base * box.width / unit
        func place(_ want: CGFloat, _ lo: CGFloat, _ hi: CGFloat, _ size: CGFloat) -> CGFloat {
            // keep [lo, hi] (focus extent, board units * sc) inside 0...size; if it doesn't fit, centre it
            let minO = -lo, maxO = size - hi
            return minO > maxO ? (minO + maxO) / 2 : min(max(want, minO), maxO)
        }
        s = sc
        origin = CGPoint(x: place(box.midX - focus.midX * sc, focus.minX * sc, focus.maxX * sc, canvas.width),
                         y: place(box.midY - focus.midY * sc, focus.minY * sc, focus.maxY * sc, canvas.height))
    }

    public func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * s, y: origin.y + y * s) }
    public func len(_ v: CGFloat) -> CGFloat { v * s }
    public func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: origin.x + x * s, y: origin.y + y * s, width: w * s, height: h * s) }
}

/// Keyframe helpers shared by the recipes: percent-of-loop windows like the CSS boards.
public enum Key {
    /// 0 before `a`, 1 after `b`, linear between (a, b in 0...1).
    public static func span(_ p: Double, _ a: Double, _ b: Double) -> Double { b <= a ? (p >= b ? 1 : 0) : min(1, max(0, (p - a) / (b - a))) }
    public static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
    public static func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    public static func easeIn(_ t: Double) -> Double { t * t * t }
    public static func easeInOut(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
    /// Overshoots past 1 then settles (the boards' cubic-bezier(.2,.9,.25,1.15) pops).
    public static func back(_ t: Double, _ k: Double = 1.7) -> Double { let u = t - 1; return 1 + (k + 1) * u * u * u + k * u * u }
}

public enum DonationArt {
    public static func frame(_ k: DonationAlertKind, p: Double, info: DonationAlertInfo, style: DonationAlertStyle, c: StingerCanvas,
                      box: CGRect?) -> CIImage {
        let b = DonationBoard(c.size, focus: k.focus, box: box)
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
