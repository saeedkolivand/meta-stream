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
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<30 {
            let u = 1 - t
            if 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        let u = 1 - t
        return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
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
    static func timing(_ d: NowPlayingDesign) -> (switchAt: Double, inLen: Double) {
        switch d {
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
    static func total(_ d: NowPlayingDesign) -> Double { timing(d).switchAt + timing(d).inLen }
    static func enterTotal(_ d: NowPlayingDesign) -> Double { timing(d).inLen }
    static func exitTotal(_ d: NowPlayingDesign) -> Double { timing(d).switchAt }

    static func change(_ d: NowPlayingDesign, t: Double) -> NowPlayingPose {
        let sw = timing(d).switchAt
        return t < sw ? out(d, t) : inHalf(d, t - sw)
    }

    static func enter(_ d: NowPlayingDesign, t: Double) -> NowPlayingPose { inHalf(d, t) }

    /// The out half on the song that is leaving, then a fade of the whole widget over its second half (the card or the
    /// note left behind by the wipes would otherwise pop off).
    static func exit(_ d: NowPlayingDesign, t: Double) -> NowPlayingPose {
        var p = out(d, t)
        p.useNew = true
        let sw = timing(d).switchAt
        p.alpha = 1 - CGFloat(min(1, max(0, (t - sw / 2) / (sw / 2))))
        return p
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

    private static func ease(_ c: Cubic, _ t: Double, _ dur: Double, _ delay: Double = 0) -> CGFloat { CGFloat(c.at((t - delay) / dur)) }
    /// Exact at both ends (a*(1-p) + b*p, not a + (b-a)*p), so a settled pose compares equal to .settled.
    private static func mix(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat { a * (1 - p) + b * p }

    /// The old song leaving; `t` seconds from the change.
    private static func out(_ d: NowPlayingDesign, _ t: Double) -> NowPlayingPose {
        var p = NowPlayingPose()
        p.useNew = false
        switch d {
        case .slab:
            let m = ease(.slideOut, t, 0.30), o = ease(.easeIn, t, 0.26)
            p.cover = NowPlayingLane(alpha: 1 - o, scale: mix(1, 0.82, m))
            p.line1 = NowPlayingLane(dy: -32 * m, alpha: 1 - o)
            p.line2 = p.line1
        case .island:
            let w = ease(.easeIn, t, 0.38)
            p.reveal = 1 - ease(.collapse, t, 0.38)
            p.cover = NowPlayingLane(alpha: mix(1, 0.4, w), scale: mix(1, 0.6, w))
            p.line1 = NowPlayingLane(alpha: 1 - ease(.easeIn, t, 0.14))
            p.line2 = p.line1
        case .disc:
            let m = ease(.dropOut, t, 0.36)
            p.cover = NowPlayingLane(dy: 240 * m, rot: Double(120 * m))
            p.line1 = NowPlayingLane(dx: -48 * ease(.easeIn, t, 0.30), alpha: 1 - ease(.easeIn, t, 0.24))
        case .ticker:
            p.trail = ease(.tickerOut, t, 0.28)
            p.cover = NowPlayingLane(scaleX: 1 - ease(.easeIn, t, 0.15))
        case .text, .popup:
            p.reveal = 1 - ease(.wipeOut, t, 0.32)
        case .twoLine:
            let m = ease(.slideOut, t, 0.28), o = ease(.easeIn, t, 0.24)
            p.line1 = NowPlayingLane(dy: -24 * m, alpha: 1 - o)
            p.line2 = p.line1
        case .cover:
            p.reveal = 1 - ease(.wipeOut, t, 0.32)
            p.cover = NowPlayingLane(scaleX: 1 - ease(.easeIn, t, 0.16, 0.16))
        }
        return p
    }

    /// The new song arriving; `u` seconds from the switch (u <= 0 is the pre-roll pose: everything hidden / off to the side).
    private static func inHalf(_ d: NowPlayingDesign, _ u: Double) -> NowPlayingPose {
        var p = NowPlayingPose()
        switch d {
        case .slab:
            let v = u - 0.04   // the mockup waits 40 ms before the "in" transitions start
            p.cover = NowPlayingLane(alpha: ease(.easeOut, v, 0.42), scale: mix(1.12, 1, ease(.standard, v, 0.52)))
            p.line1 = NowPlayingLane(dy: mix(32, 0, ease(.standard, v, 0.52, 0.04)), alpha: ease(.easeOut, v, 0.42, 0.04))
            p.line2 = NowPlayingLane(dy: mix(32, 0, ease(.standard, v, 0.52, 0.11)), alpha: ease(.easeOut, v, 0.42, 0.11))
        case .island:
            // The cover pops back in over the closed capsule (160 ms), then the capsule springs open and the text fades in.
            p.cover = NowPlayingLane(alpha: mix(0.4, 1, ease(.easeOut, u, 0.12)), scale: mix(0.6, 1, ease(.pop, u, 0.16)))
            p.reveal = ease(.spring, u, 0.62, 0.16)
            p.line1 = NowPlayingLane(alpha: ease(.easeOut, u, 0.32, 0.42))
            p.line2 = p.line1
        case .disc:
            let v = u - 0.04
            let m = ease(.dropIn, v, 0.64)
            p.cover = NowPlayingLane(dy: mix(-240, 0, m), rot: Double(mix(-120, 0, m)))
            p.line1 = NowPlayingLane(dx: mix(48, 0, ease(.standard, v, 0.52, 0.12)), alpha: ease(.easeOut, v, 0.40, 0.12))
        case .ticker:
            let v = u - 0.04
            p.reveal = ease(.standard, v, 0.56, 0.06)
            p.cover = NowPlayingLane(scaleX: ease(.flip, v, 0.30))
        case .text:
            p.reveal = ease(.standard, u - 0.06, 0.56)
        case .popup:
            p.reveal = ease(.standard, u - 0.06, 0.60)
        case .twoLine:
            let v = u - 0.04
            p.line1 = NowPlayingLane(dy: mix(24, 0, ease(.standard, v, 0.48)), alpha: ease(.easeOut, v, 0.38))
            p.line2 = NowPlayingLane(dy: mix(24, 0, ease(.standard, v, 0.48, 0.08)), alpha: ease(.easeOut, v, 0.38, 0.08))
        case .cover:
            let v = u - 0.06
            p.reveal = ease(.standard, v, 0.56, 0.12)
            p.cover = NowPlayingLane(scaleX: ease(.flip, v, 0.26))
        }
        return p
    }

    #if DEBUG
    static func demo() {
        for d in NowPlayingDesign.allCases {
            let sw = timing(d).switchAt
            // A change starts on the old song, settled as it was, switches to the new one at switchAt and ends settled.
            var start = change(d, t: 0)
            assert(!start.useNew)
            start.useNew = true
            assert(start == .settled, "\(d) change start")
            assert(!change(d, t: sw - 0.001).useNew && change(d, t: sw).useNew, "\(d) switch point")
            // +1 ms: the last curve reaches exactly 1 only a rounding error past its nominal end
            assert(change(d, t: total(d) + 0.001) == .settled && change(d, t: total(d) + 5) == .settled, "\(d) change end")
            // The first appearance starts off-screen/hidden and ends settled; an exit starts settled and ends invisible.
            assert(enter(d, t: 0) != .settled && enter(d, t: enterTotal(d) + 0.001) == .settled, "\(d) enter")
            assert(exit(d, t: 0) == .settled && exit(d, t: exitTotal(d)).alpha == 0, "\(d) exit")
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
