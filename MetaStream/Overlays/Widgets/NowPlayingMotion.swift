// Now playing motion: every frame is a pure function of the seconds since the song changed (like AlertIsland.pose), copied
// from the mockups' CSS transitions. A change plays an "out" half on the old song, switches to the new one, then the "in"
// half; the first appearance plays only the "in" half, and a song going away only the "out" half. Offsets are in widget
// points at the 1080-short-side scale, i.e. the mockup's px x 2.
import CoreGraphics
import Foundation

/// One animated element: where it sits relative to its resting place, and how visible it is.
struct NowPlayingLane: Equatable {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var alpha: CGFloat = 1
    var scale: CGFloat = 1
    var scaleX: CGFloat = 1   // extra horizontal scale: the cover "flip"
    var rot: Double = 0       // degrees
}

/// Everything NowPlayingView needs for one frame. The default value is the settled card.
struct NowPlayingPose: Equatable {
    var useNew = true          // false: still drawing the outgoing song
    var alpha: CGFloat = 1     // whole widget (the fade at the end of an exit)
    var reveal: CGFloat = 1    // 0 shut ... 1 open; the island's spring may overshoot past 1
    var trail: CGFloat = 0     // ticker only: how far the left edge of the text wipe has moved right (0...1)
    var cover = NowPlayingLane()
    var line1 = NowPlayingLane()   // title (island/disc/ticker: the whole text block)
    var line2 = NowPlayingLane()   // artist

    static let settled = NowPlayingPose()
}

/// CSS cubic-bezier(x1, y1, x2, y2) timing function (y may leave 0...1: that is the overshoot).
struct Cubic: Sendable {
    let x1, y1, x2, y2: Double
    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2 }

    /// Eased value at progress `x` (clamped to 0...1). x(t) is monotonic for x1, x2 in 0...1, so bisect for t.
    func at(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        var lo = 0.0, hi = 1.0, param = x
        for _ in 0..<30 {
            let inv = 1 - param
            if 3 * inv * inv * param * x1 + 3 * inv * param * param * x2 + param * param * param < x { lo = param } else { hi = param }
            param = (lo + hi) / 2
        }
        let inv = 1 - param
        return 3 * inv * inv * param * y1 + 3 * inv * param * param * y2 + param * param * param
    }

    static let standard = Cubic(0.2, 0.8, 0.2, 1)     // slide / wipe in
    static let easeIn = Cubic(0.42, 0, 1, 1)
    static let easeOut = Cubic(0, 0, 0.58, 1)
    static let easeInOut = Cubic(0.42, 0, 0.58, 1)
    static let slideOut = Cubic(0.4, 0, 1, 1)
    static let wipeOut = Cubic(0.6, 0, 0.8, 0.4)      // text / cover / pop-up box closing
    static let tickerOut = Cubic(0.5, 0, 0.9, 0.5)
    static let collapse = Cubic(0.5, 0, 0.75, 0)      // island capsule closing
    static let spring = Cubic(0.34, 1.4, 0.64, 1)     // island capsule opening (peaks at 1.05)
    static let pop = Cubic(0.34, 1.8, 0.64, 1)        // island cover popping back
    static let dropOut = Cubic(0.5, 0, 0.9, 0.4)
    static let dropIn = Cubic(0.2, 1.25, 0.4, 1)
    static let flip = Cubic(0.2, 1.4, 0.4, 1)
}

enum NowPlayingMotion {
    /// `switchAt`: seconds into a change when the new song replaces the old (= the out half's length).
    /// `inLen`: seconds from the switch until the in half has settled.
    static func timing(_ design: NowPlayingDesign) -> (switchAt: Double, inLen: Double) {
        switch design {
        case .slab: (0.32, 0.67)
        case .island: (0.42, 0.78)
        case .disc: (0.38, 0.68)
        case .ticker: (0.30, 0.66)
        case .text: (0.34, 0.62)
        case .twoLine: (0.30, 0.60)
        case .cover: (0.34, 0.74)
        case .popup: (0.34, 0.66)
        }
    }

    /// A song change from start to settled; an enter (first appearance) and an exit (song gone) are one half each.
    static func total(_ design: NowPlayingDesign) -> Double { timing(design).switchAt + timing(design).inLen }
    static func enterTotal(_ design: NowPlayingDesign) -> Double { timing(design).inLen }
    static func exitTotal(_ design: NowPlayingDesign) -> Double { timing(design).switchAt }

    static func change(_ design: NowPlayingDesign, t time: Double) -> NowPlayingPose {
        let sw = timing(design).switchAt
        return time < sw ? out(design, time) : inHalf(design, time - sw)
    }

    static func enter(_ design: NowPlayingDesign, t time: Double) -> NowPlayingPose { inHalf(design, time) }

    /// The out half on the song that is leaving, then a fade of the whole widget over its second half (the card or the
    /// note left behind by the wipes would otherwise pop off).
    static func exit(_ design: NowPlayingDesign, t time: Double) -> NowPlayingPose {
        var pose = out(design, time)
        pose.useNew = true
        let sw = timing(design).switchAt
        pose.alpha = 1 - CGFloat(min(1, max(0, (time - sw / 2) / (sw / 2))))
        return pose
    }

    /// Pop-up: true once it has been open for its hold time and should start closing.
    static func popupExitDue(openFor: Double, hold: Int) -> Bool { openFor >= Double(hold) }

    // MARK: continuous decorations (functions of absolute time, so a redraw never jumps them)

    /// Disc: one turn every 5 s, in degrees.
    static func spin(_ clock: Double) -> Double { 360 * (clock.truncatingRemainder(dividingBy: 5) / 5) }

    /// One equaliser bar's scaleY: `low` -> 1 -> `low` every `period`, ease-in-out each way. `offset` is the CSS negative delay.
    static func eq(_ clock: Double, period: Double, offset: Double, low: CGFloat) -> CGFloat {
        let ph = ((clock + offset) / period).truncatingRemainder(dividingBy: 1)
        let tri = ph < 0.5 ? ph * 2 : (1 - ph) * 2
        return low + (1 - low) * CGFloat(Cubic.easeInOut.at(tri))
    }

    // MARK: the two halves

    private static func ease(_ curve: Cubic, _ time: Double, _ dur: Double, _ delay: Double = 0) -> CGFloat {
        CGFloat(curve.at((time - delay) / dur))
    }
    /// Exact at both ends (a*(1-p) + b*p, not a + (b-a)*p), so a settled pose compares equal to .settled.
    private static func mix(_ from: CGFloat, _ to: CGFloat, _ frac: CGFloat) -> CGFloat { from * (1 - frac) + to * frac }

    /// The old song leaving; `t` seconds from the change.
    private static func out(_ design: NowPlayingDesign, _ time: Double) -> NowPlayingPose {
        var pose = NowPlayingPose()
        pose.useNew = false
        switch design {
        case .slab:
            let move = ease(.slideOut, time, 0.30), fade = ease(.easeIn, time, 0.26)
            pose.cover = NowPlayingLane(alpha: 1 - fade, scale: mix(1, 0.82, move))
            pose.line1 = NowPlayingLane(dy: -32 * move, alpha: 1 - fade)
            pose.line2 = pose.line1
        case .island:
            let wide = ease(.easeIn, time, 0.38)
            pose.reveal = 1 - ease(.collapse, time, 0.38)
            pose.cover = NowPlayingLane(alpha: mix(1, 0.4, wide), scale: mix(1, 0.6, wide))
            pose.line1 = NowPlayingLane(alpha: 1 - ease(.easeIn, time, 0.14))
            pose.line2 = pose.line1
        case .disc:
            let move = ease(.dropOut, time, 0.36)
            pose.cover = NowPlayingLane(dy: 240 * move, rot: Double(120 * move))
            pose.line1 = NowPlayingLane(dx: -48 * ease(.easeIn, time, 0.30), alpha: 1 - ease(.easeIn, time, 0.24))
        case .ticker:
            pose.trail = ease(.tickerOut, time, 0.28)
            pose.cover = NowPlayingLane(scaleX: 1 - ease(.easeIn, time, 0.15))
        case .text, .popup:
            pose.reveal = 1 - ease(.wipeOut, time, 0.32)
        case .twoLine:
            let move = ease(.slideOut, time, 0.28), fade = ease(.easeIn, time, 0.24)
            pose.line1 = NowPlayingLane(dy: -24 * move, alpha: 1 - fade)
            pose.line2 = pose.line1
        case .cover:
            pose.reveal = 1 - ease(.wipeOut, time, 0.32)
            pose.cover = NowPlayingLane(scaleX: 1 - ease(.easeIn, time, 0.16, 0.16))
        }
        return pose
    }

    /// The new song arriving; `u` seconds from the switch (u <= 0 is the pre-roll pose: everything hidden / off to the side).
    private static func inHalf(_ design: NowPlayingDesign, _ since: Double) -> NowPlayingPose {
        var pose = NowPlayingPose()
        switch design {
        case .slab:
            let shifted = since - 0.04   // the mockup waits 40 ms before the "in" transitions start
            pose.cover = NowPlayingLane(alpha: ease(.easeOut, shifted, 0.42), scale: mix(1.12, 1, ease(.standard, shifted, 0.52)))
            pose.line1 = NowPlayingLane(dy: mix(32, 0, ease(.standard, shifted, 0.52, 0.04)), alpha: ease(.easeOut, shifted, 0.42, 0.04))
            pose.line2 = NowPlayingLane(dy: mix(32, 0, ease(.standard, shifted, 0.52, 0.11)), alpha: ease(.easeOut, shifted, 0.42, 0.11))
        case .island:
            // The cover pops back in over the closed capsule (160 ms), then the capsule springs open and the text fades in.
            pose.cover = NowPlayingLane(alpha: mix(0.4, 1, ease(.easeOut, since, 0.12)), scale: mix(0.6, 1, ease(.pop, since, 0.16)))
            pose.reveal = ease(.spring, since, 0.62, 0.16)
            pose.line1 = NowPlayingLane(alpha: ease(.easeOut, since, 0.32, 0.42))
            pose.line2 = pose.line1
        case .disc:
            let shifted = since - 0.04
            let move = ease(.dropIn, shifted, 0.64)
            pose.cover = NowPlayingLane(dy: mix(-240, 0, move), rot: Double(mix(-120, 0, move)))
            pose.line1 = NowPlayingLane(dx: mix(48, 0, ease(.standard, shifted, 0.52, 0.12)), alpha: ease(.easeOut, shifted, 0.40, 0.12))
        case .ticker:
            let shifted = since - 0.04
            pose.reveal = ease(.standard, shifted, 0.56, 0.06)
            pose.cover = NowPlayingLane(scaleX: ease(.flip, shifted, 0.30))
        case .text:
            pose.reveal = ease(.standard, since - 0.06, 0.56)
        case .popup:
            pose.reveal = ease(.standard, since - 0.06, 0.60)
        case .twoLine:
            let shifted = since - 0.04
            pose.line1 = NowPlayingLane(dy: mix(24, 0, ease(.standard, shifted, 0.48)), alpha: ease(.easeOut, shifted, 0.38))
            pose.line2 = NowPlayingLane(dy: mix(24, 0, ease(.standard, shifted, 0.48, 0.08)), alpha: ease(.easeOut, shifted, 0.38, 0.08))
        case .cover:
            let shifted = since - 0.06
            pose.reveal = ease(.standard, shifted, 0.56, 0.12)
            pose.cover = NowPlayingLane(scaleX: ease(.flip, shifted, 0.26))
        }
        return pose
    }

    #if DEBUG
    static func demo() {
        for design in NowPlayingDesign.allCases {
            let sw = timing(design).switchAt
            // A change starts on the old song, settled as it was, switches to the new one at switchAt and ends settled.
            var start = change(design, t: 0)
            assert(!start.useNew)
            start.useNew = true
            assert(start == .settled, "\(design) change start")
            assert(!change(design, t: sw - 0.001).useNew && change(design, t: sw).useNew, "\(design) switch point")
            // +1 ms: the last curve reaches exactly 1 only a rounding error past its nominal end
            assert(change(design, t: total(design) + 0.001) == .settled
                   && change(design, t: total(design) + 5) == .settled, "\(design) change end")
            // The first appearance starts off-screen/hidden and ends settled; an exit starts settled and ends invisible.
            assert(enter(design, t: 0) != .settled && enter(design, t: enterTotal(design) + 0.001) == .settled, "\(design) enter")
            assert(exit(design, t: 0) == .settled && exit(design, t: exitTotal(design)).alpha == 0, "\(design) exit")
        }
        // Pop-up: closes only after the hold, and is shut when its exit is over.
        assert(!popupExitDue(openFor: 5.9, hold: 6) && popupExitDue(openFor: 6, hold: 6))
        assert(exit(.popup, t: exitTotal(.popup)).reveal == 0)
        // Curves: exact ends, the spring overshoots, ease-in-out is symmetric.
        assert(Cubic.standard.at(0) == 0 && Cubic.standard.at(1) == 1 && Cubic.spring.at(0.5) > 1)
        assert(abs(Cubic.easeInOut.at(0.5) - 0.5) < 0.001)
        assert(eq(0, period: 0.9, offset: 0, low: 0.35) == 0.35 && abs(eq(0.45, period: 0.9, offset: 0, low: 0.35) - 1) < 0.001)
        applog("overlay", "NowPlayingMotion.demo() passed")
    }
    #endif
}
