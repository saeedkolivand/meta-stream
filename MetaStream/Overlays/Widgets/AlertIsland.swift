// "Island" alert timing: every frame of the banner is a pure function of the seconds since the alert started, so
// the render loop just asks for a pose and draws it (and tests can pin the curve without a renderer).
import CoreGraphics
import Foundation
import HaishinKit

/// Everything AlertBannerView needs to draw one frame. The default value is the fully open, settled card.
struct AlertPose: Equatable {
    var lift: CGFloat = 0            // vertical offset in capsule heights (negative = above rest)
    var open: CGFloat = 1            // 0 = dot, 1 = full width (may overshoot a little)
    var alpha: CGFloat = 1           // whole-capsule opacity (the exit fade)
    var contentAlpha: CGFloat = 1
    var contentRise: CGFloat = 0     // px the content still has to rise
    var progress: Double = 1         // amount count-up, 0...1
    var flash: Double = 0            // big-tier colour flash opacity

    static let settled = AlertPose()
}

enum AlertIsland {
    static let enter = 1.75          // dot drop, open, fade-in, count-up and flash all finished
    static let exit = 0.5
    static let gap = 0.3

    static func total(hold: Int) -> Double { enter + Double(hold) + exit }

    @MainActor static func isBig(_ e: ChatEvent) -> Bool {
        (e.kind == .tip && (Rates.shared.convert(e.tipMoney, to: "USD") ?? 0) >= 10) || (e.kind == .raid && e.count >= 50)
    }

    @MainActor static func height(_ e: ChatEvent) -> CGFloat { height(big: isBig(e)) }
    static func height(big: Bool) -> CGFloat { big ? 154 : 124 }

    // Content geometry in points of the 900x240 natural area, shared by the SwiftUI banner and the GPU recipe.
    static let gapX: CGFloat = 24
    static let padTrailing: CGFloat = 44
    static func fullWidth(big: Bool) -> CGFloat { big ? 800 : 740 }
    static func iconSize(big: Bool) -> CGFloat { big ? 120 : 84 }
    /// What the name column and the amount share (icon and the three gaps/padding taken out).
    static func share(big: Bool) -> CGFloat {
        fullWidth(big: big) - (height(big: big) - iconSize(big: big)) / 2 - iconSize(big: big) - 2 * gapX - padTrailing
    }
    /// The amount may take 40% of the shared width and shrinks past that, so the name always shows.
    static func amountMax(big: Bool) -> CGFloat { 0.4 * share(big: big) }

    /// 12_300 -> "12.3K", 1_200_000 -> "1.2M"; plain below 10,000.
    static func compact(_ n: Int) -> String {
        guard n >= 10_000 else { return "\(n)" }
        let (v, unit) = n >= 999_950 ? (Double(n) / 1e6, "M") : (Double(n) / 1e3, "K")
        let s = String(format: "%.1f", v)
        return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + unit
    }

    /// ARGB per kind; subscribe takes the widget's accent so the colour setting still means something.
    static func color(_ k: ChatEvent.Kind, accent: UInt32) -> UInt32 {
        switch k {
        case .follow: return 0xFFD9_D9E3
        case .subscribe: return accent
        case .tip: return 0xFF20_C56C
        case .cheer: return 0xFFFF_4FA3
        case .raid: return 0xFFFF_7A2F
        case .message: return 0xFFFF_FFFF
        }
    }

    static func label(_ k: ChatEvent.Kind) -> String {
        switch k {
        case .follow: return "NEW FOLLOWER"
        case .subscribe: return "NEW SUBSCRIBER"
        case .tip: return "TIP"
        case .cheer: return "BITS"
        case .raid: return "RAID"
        case .message: return ""
        }
    }

    static func label(_ e: ChatEvent) -> String { e.kind == .cheer && e.origin == "kick" ? "KICKS" : label(e.kind) }

    /// The amount at `progress` (0...1) of its count-up; nil for follows and subs.
    static func amountText(_ e: ChatEvent, progress p: Double) -> String? {
        amountParts(e, progress: p).map { $0.unit.isEmpty ? $0.number : "\($0.number) \($0.unit)" }
    }

    /// The amount as number + unit (drawn smaller), counts compact from 10,000; nil for follows and subs.
    static func amountParts(_ e: ChatEvent, progress p: Double) -> (number: String, unit: String)? {
        switch e.kind {
        case .tip:
            let m = e.tipMoney
            return (Money(m.amount * Decimal(p), m.currency).display, "")
        case .cheer: return (compact(Int((Double(e.count) * p).rounded())), e.cheerUnit)
        case .raid: return (compact(Int((Double(e.count) * p).rounded())), "viewers")
        default: return nil
        }
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    // A slight overshoot (c1 1.2) so the capsule springs a hair past full width and settles.
    private static func easeOutBack(_ x: Double) -> Double { let c1 = 1.2, y = x - 1; return 1 + (c1 + 1) * y * y * y + c1 * y * y }

    /// Pose `t` seconds after the alert started; `hold` seconds sit between the enter and exit motion.
    static func pose(at t: Double, hold: Int, big: Bool) -> AlertPose {
        let te = t - enter - Double(hold)   // seconds into the exit, negative before it
        var p = AlertPose()
        p.lift = CGFloat(-1.5 * (1 - easeOut(clamp(t / 0.28))))
        p.open = CGFloat(easeOutBack(clamp((t - 0.28) / 0.34)))
        let fade = easeOut(clamp((t - 0.42) / 0.35))
        p.contentAlpha = CGFloat(fade)
        p.contentRise = CGFloat(16 * (1 - fade))
        p.progress = easeOut(clamp((t - 0.45) / 1.1))
        p.flash = big && t >= 0.62 ? 0.9 * (1 - clamp((t - 0.62) / 1.1)) : 0
        guard te > 0 else { return p }
        p.contentAlpha = CGFloat(1 - clamp(te / 0.15))
        p.open = CGFloat(1 - easeOut(clamp(te / 0.28)))
        let away = clamp((te - 0.28) / 0.22)
        p.lift = CGFloat(-0.5 * away * away)
        p.alpha = CGFloat(1 - away)
        return p
    }
}

/// Plays one alert: on the GPU (IslandArt) when the mixer is up; otherwise the CPU fallback, whose motion phases
/// draw ~24 fps and whose hold draws a single static frame.
@MainActor
enum AlertPlayer {
    static func play(_ e: ChatEvent, style: AlertWidgetStyle, on o: ImageScreenObject, natural: CGSize, box: CGRect, canvas: CGSize,
                     mixer: MediaMixer?) async {
        let hold = style.holdSeconds, big = AlertIsland.isBig(e)
        if let mixer {
            let g = await OverlayScreen.makeIsland(CGRect(origin: .zero, size: canvas), e, style, hold: hold, big: big, box: box)
            await OverlayScreen.add([g], to: mixer)   // added last: on top of everything
            // Layout only re-runs when invalidated, so poke it at 60 Hz (cheap: no drawing here), as for a stinger.
            let poke = Task { @ScreenActor in
                while !Task.isCancelled {
                    g.invalidateLayout()
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            try? await Task.sleep(for: .seconds(AlertIsland.total(hold: hold) + 0.15))   // a beat past the end, so it logs and clears itself
            poke.cancel()
            await OverlayScreen.remove([g], from: mixer)
            return
        }
        let start = Date(), total = AlertIsland.total(hold: hold)
        let exitAt = AlertIsland.enter + Double(hold)
        var heldDrawn = false
        func draw(_ pose: AlertPose) async {
            guard let piece = WidgetRaster.piece(AlertBannerView(event: e, style: style, pose: pose), natural: natural, box: box, canvas: canvas) else { return }
            await OverlayScreen.setImage(o, piece.bitmap)
        }
        while !Task.isCancelled {
            let t = Date().timeIntervalSince(start)
            if t >= total { break }
            if t >= AlertIsland.enter, t < exitAt {
                if !heldDrawn { heldDrawn = true; await draw(.settled) }
                try? await Task.sleep(for: .seconds(exitAt - t))
                continue
            }
            await draw(AlertIsland.pose(at: t, hold: hold, big: big))
            try? await Task.sleep(for: WidgetRaster.pause(42))
        }
        await OverlayScreen.setImage(o, nil)
    }
}
