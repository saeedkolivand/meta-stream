// Camera-themed stingers: Lens, Aperture blades, Route & pin, Viewfinder. Each reproduces its design board's keyframes
// as a Core Image recipe (see StingerCanvas).
import CoreGraphics
import CoreImage
import UIKit

extension StingerArt {
    private static let white: UInt32 = 0xFFFF_FFFF

    /// Board point (1920x1080) mapped around the canvas centre.
    private static func camAt(_ k: StingerCanvas, _ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: k.center.x + (x - 960) * k.unit, y: k.center.y + (y - 540) * k.unit)
    }

    private static func camBox(_ p: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
    }

    // MARK: lens

    /// Graphite plate with a hole that shrinks onto the splash's lens (rim, glass, tally, wordmark), then opens again.
    static func lens(_ k: StingerCanvas, _ q: Double, _ s: StingerStyle) -> CIImage {
        guard q > 0.24, q < 0.66 else { return .empty() }
        let u = k.unit, ctr = k.center, hd = k.halfDiagonal
        // 1250 board px = "off screen": beyond the corners whatever the canvas shape; 215 scales by unit.
        let big = max(1250 * u, hd + 24)
        let hv = Curve(0.65, 0, 0.35, 1).track(q, [(0.25, 1250), (0.38, 215), (0.55, 215), (0.64, 1250)])
        let hole = 215 * u + CGFloat((hv - 215) / 1035) * (big - 215 * u)
        var layers: [CIImage] = []

        // Graphite plate everywhere outside the rim's inner edge.
        let plateShape = k.minus(k.fill(k.bounds, white), k.disc(ctr, hole - 12 * u, white))
        layers.append(k.clip(k.linear(.zero, CGPoint(x: 0, y: k.size.height), 0xFF1C_1C1F, 0xFF0A_0A0C), to: plateShape))

        // Inner graphite disc behind the glass.
        let innerA = Curve.easeInOut.track(q, [(0.36, 0), (0.40, 1), (0.52, 1), (0.55, 0)])
        if innerA > 0.001 {
            let g = k.linear(CGPoint(x: 0, y: ctr.y - 216 * u), CGPoint(x: 0, y: ctr.y + 216 * u), 0xFF1C_1C1F, 0xFF0A_0A0C)
            layers.append(k.opacity(k.clip(g, to: k.disc(ctr, 216 * u, white)), innerA))
        }

        // Glass: radial dark disc, hairline ring, blurred crescent reflection (circle A minus circle B).
        let glassA = Curve.easeInOut.track(q, [(0.37, 0), (0.42, 1), (0.52, 1), (0.55, 0)])
        if glassA > 0.001 {
            let glass = k.disc(ctr, 203 * u, white)
            let dark = k.clip(k.radial(ctr, 0, 200 * u, 0xFF16_181E, 0xFF02_0203), to: glass)
            let hair = k.ring(ctr, inner: 136 * u, outer: 139 * u, white, alpha: 0.07)
            let a = camAt(k, 939, 519), b = camAt(k, 959, 553)
            let cres = k.minus(k.disc(a, 182 * u, white, alpha: 0.16), k.disc(b, 182 * u, white))
            let soft = k.blur(cres, 6 * u).cropped(to: camBox(a, 182 * u + 18 * u))
            layers.append(k.opacity(k.stack([dark, hair, k.clip(soft, to: glass)]), glassA))
        }

        let pop = Curve(0.33, 1, 0.68, 1)

        // Bloom behind the tally.
        let bloomA = pop.track(q, [(0.39, 0), (0.42, 0.9), (0.46, 0.65), (0.52, 0.65), (0.535, 0)])
        let bloomS = pop.track(q, [(0.39, 1.4), (0.42, 1.9), (0.46, 2.2)])
        if bloomA > 0.001 {
            let r = 42 * u * CGFloat(bloomS)
            let bloom = k.radial(ctr, 0, r, s.tally, s.tally, alphaA: 1, alphaB: 0).cropped(to: camBox(ctr, r))
            layers.append(k.opacity(bloom, bloomA))
        }

        // Tally: warm vertical gradient with a blurred soft highlight.
        let tallyA = pop.track(q, [(0.39, 0), (0.44, 1), (0.52, 1), (0.535, 0)])
        if tallyA > 0.001 {
            let ts = CGFloat(pop.track(q, [(0.39, 0.9), (0.44, 1)]))
            let r = 42 * u * ts
            let top = s.tally == 0xFFE8_101E ? UInt32(0xFFFF_5A3C) : mixWhite(s.tally, 0.3)
            let body = k.clip(k.linear(CGPoint(x: 0, y: ctr.y - r), CGPoint(x: 0, y: ctr.y + r), top, s.tally), to: k.disc(ctr, r, white))
            let hl = CGPoint(x: ctr.x, y: ctr.y - 10 * u * ts)
            let glow = k.blur(k.disc(hl, 30 * u * ts, white, alpha: 0.28), 5 * u).cropped(to: camBox(hl, 30 * u * ts + 15 * u))
            layers.append(k.opacity(k.stack([body, k.clip(glow, to: k.disc(ctr, r, white))]), tallyA))
        }

        // Titanium rim, lit from the top-left.
        let rimA = Curve.linear.track(q, [(0.245, 0), (0.27, 1), (0.62, 1), (0.65, 0)])
        if rimA > 0.001, hole - 12 * u < hd + 1 {
            let outer = hole + 12 * u
            let g = k.linear(CGPoint(x: ctr.x - outer, y: ctr.y - outer), CGPoint(x: ctr.x + outer, y: ctr.y + outer), 0xFFC8_C8CE, 0xFF3A_3A3E)
            layers.append(k.opacity(k.clip(g, to: k.ring(ctr, inner: hole - 12 * u, outer: outer, white)), rimA))
        }

        // Wordmark: rises 16px while the tracking tightens 0.32em -> 0.2em.
        if s.showName, !s.name.isEmpty {
            let a = pop.track(q, [(0.41, 0), (0.47, 0.92), (0.52, 0.92), (0.54, 0)])
            let track = pop.track(q, [(0.41, 0.32), (0.47, 0.2)])
            let rise = pop.track(q, [(0.41, 16), (0.47, 0)])
            // Box top is 880; a 52px line is ~62px tall, so its middle sits near 911.
            layers.append(k.text(s.name, at: camAt(k, 960, 911 + rise), size: 52 * u, weight: .regular, color: white,
                                 alpha: CGFloat(a), tracking: CGFloat(track)))
        }
        return k.stack(layers)
    }

    // MARK: aperture

    /// Six ink blades slide in from outside, close like an iris (spinning 50 degrees), then leave the other way.
    static func aperture(_ k: StingerCanvas, _ q: Double, _ s: StingerStyle) -> CIImage {
        guard q >= 0.25, q <= 0.67 else { return .empty() }
        let u = k.unit, ctr = k.center, kk = k.halfDiagonal / 1101
        let blade = Curve(0.76, 0, 0.24, 1)
        let f = blade.track(q, [(0.25, 0), (0.40, 1), (0.52, 1), (0.67, 0)])
        let spin = blade.track(q, [(0.25, -50), (0.40, 0), (0.52, 0), (0.67, 50)])
        let open = -1400 * kk, closed = 30 * u
        let ty = open + (closed - open) * CGFloat(f)
        let edgeA = Curve.linear.track(q, [(0.36, 1), (0.40, 0), (0.52, 0), (0.56, 1)])
        let fills = [mixWhite(s.ink, 0.05), s.ink]   // board: even blades a shade lighter
        let edge = k.fill(CGRect(x: -2000 * kk, y: -4 * u, width: 4000 * kk, height: 4 * u), s.accent, alpha: CGFloat(edgeA))
        var layers: [CIImage] = []

        for i in 0..<6 {
            let body = k.fill(CGRect(x: -2000 * kk, y: -3000 * kk, width: 4000 * kk, height: 3000 * kk), fills[i % 2])
            let t = CGAffineTransform(translationX: ctr.x, y: ctr.y)
                .rotated(by: CGFloat((Double(i) * 60 + spin) * .pi / 180))
                .translatedBy(x: 0, y: ty)
            layers.append((edgeA > 0.001 ? edge.composited(over: body) : body).transformed(by: t))
        }

        if s.showName, !s.name.isEmpty {
            let pop = Curve(0.33, 1, 0.68, 1)
            let a = pop.track(q, [(0.41, 0), (0.45, 1), (0.50, 1), (0.53, 0)])
            let sc = pop.track(q, [(0.41, 0.96), (0.45, 1), (0.50, 1), (0.53, 1.02)])
            layers.append(k.text(s.name, at: ctr, size: 56 * u, color: fg(on: s.ink), alpha: CGFloat(a), scale: CGFloat(sc)))
        }
        return k.stack(layers)
    }

    // MARK: route

    /// An accent route draws itself toward the centre, a pin pops there, ink floods out from it, the name rises.
    static func route(_ k: StingerCanvas, _ q: Double, _ s: StingerStyle) -> CIImage {
        guard q >= 0.24, q <= 0.64 else { return .empty() }
        let u = k.unit, ctr = k.center, hd = k.halfDiagonal
        var layers: [CIImage] = []

        // Route line: sample "M -40 1000 C 360 1000 420 640 760 720 C 1000 776 1080 610 960 540", stroke a prefix.
        let draw = Curve(0.65, 0, 0.35, 1)
        let frac = 1 - draw.track(q, [(0.24, 1), (0.35, 0), (0.54, 0)])
        let lineA = draw.track(q, [(0.24, 1), (0.54, 1), (0.58, 0)])
        if frac > 0.0005, lineA > 0.001 {
            let segs: [[(Double, Double)]] = [[(-40, 1000), (360, 1000), (420, 640), (760, 720)],
                                              [(760, 720), (1000, 776), (1080, 610), (960, 540)]]
            var pts: [CGPoint] = []
            for seg in segs {
                for i in 0...100 {
                    let t = Double(i) / 100, m = 1 - t
                    let x = m * m * m * seg[0].0 + 3 * m * m * t * seg[1].0 + 3 * m * t * t * seg[2].0 + t * t * t * seg[3].0
                    let y = m * m * m * seg[0].1 + 3 * m * m * t * seg[1].1 + 3 * m * t * t * seg[2].1 + t * t * t * seg[3].1
                    pts.append(camAt(k, x, y))
                }
            }
            layers.append(k.reveal(k.progressStroke(pts, width: 8 * u), upTo: min(frac, 1), s.accent, alpha: CGFloat(lineA)))
        }

        // Ink flood: circle(pct) from the centre; 80% = the whole frame.
        let pct = Curve(0.76, 0, 0.24, 1).track(q, [(0.37, 0), (0.46, 80), (0.54, 80), (0.64, 0)])
        let r = CGFloat(pct / 0.8) * hd * 1.02
        if r > 0.5 { layers.append(k.disc(ctr, r, s.ink)) }

        // Pin with an overshoot pop.
        let pop = Curve(0.33, 1, 0.68, 1)
        let ps = CGFloat(pop.track(q, [(0.34, 0), (0.365, 1.25), (0.38, 1), (0.54, 1), (0.62, 0)]))
        if ps > 0.001 {
            layers.append(k.disc(ctr, 18 * u * ps, s.accent))
            layers.append(k.disc(ctr, 6 * u * ps, s.ink))
        }

        // Name below the pin: box top 590, a 44px line is ~53px tall, so its middle sits near 616.
        if s.showName, !s.name.isEmpty {
            let a = pop.track(q, [(0.44, 0), (0.475, 1), (0.51, 1), (0.535, 0)])
            let dy = pop.track(q, [(0.44, 12), (0.475, 0)])
            layers.append(k.text(s.name, at: camAt(k, 960, 616 + dy), size: 44 * u, color: fg(on: s.ink), alpha: CGFloat(a)))
        }
        return k.stack(layers)
    }

    // MARK: viewfinder

    /// Ink opens from the centre like a framed shot, accent corner brackets trace it, the name fades in at full frame.
    static func viewfinder(_ k: StingerCanvas, _ q: Double, _ s: StingerStyle) -> CIImage {
        guard q >= 0.25, q <= 0.66 else { return .empty() }
        let u = k.unit, ctr = k.center
        let w = k.size.width, h = k.size.height
        let ease = Curve(0.76, 0, 0.24, 1)
        var layers: [CIImage] = []

        // Ink clip: inset(v% h%) of the canvas.
        let iv = ease.track(q, [(0.25, 50), (0.33, 38), (0.35, 38), (0.42, 0), (0.52, 0), (0.59, 38), (0.61, 38), (0.66, 50)])
        let ih = ease.track(q, [(0.25, 50), (0.33, 34), (0.35, 34), (0.42, 0), (0.52, 0), (0.59, 34), (0.61, 34), (0.66, 50)])
        layers.append(k.fill(CGRect(x: w * CGFloat(ih / 100), y: h * CGFloat(iv / 100), width: w * CGFloat(1 - 2 * ih / 100),
                                    height: h * CGFloat(1 - 2 * iv / 100)), s.ink))

        // Corner brackets on an animated inset rect (opaque arms, faded as one group so the corner overlap doesn't double up).
        let stops: [Double] = [0.25, 0.27, 0.33, 0.35, 0.42, 0.52, 0.53, 0.59, 0.61, 0.66]
        let vs: [Double] = [5, 5, 38, 38, 5, 5, 5, 38, 38, 50]
        let hs: [Double] = [3, 3, 34, 34, 3, 3, 3, 34, 34, 50]
        let os: [Double] = [0, 1, 1, 1, 0, 0, 1, 1, 1, 0]
        let fv = ease.track(q, Array(zip(stops, vs))), fh = ease.track(q, Array(zip(stops, hs)))
        let fo = ease.track(q, Array(zip(stops, os)))
        let fr = CGRect(x: w * CGFloat(fh / 100), y: h * CGFloat(fv / 100), width: w * CGFloat(1 - 2 * fh / 100),
                        height: h * CGFloat(1 - 2 * fv / 100))
        if fo > 0.001, fr.width > 0, fr.height > 0 {
            let arm = 72 * u, t = 5 * u
            var arms: [CIImage] = []
            for (x, dx) in [(fr.minX, CGFloat(1)), (fr.maxX, -1)] {
                for (y, dy) in [(fr.minY, CGFloat(1)), (fr.maxY, -1)] {
                    arms.append(k.fill(CGRect(x: min(x, x + dx * arm), y: min(y, y + dy * t), width: arm, height: t), s.accent))
                    arms.append(k.fill(CGRect(x: min(x, x + dx * t), y: min(y, y + dy * arm), width: t, height: arm), s.accent))
                }
            }
            layers.append(k.opacity(k.stack(arms), fo))
        }

        if s.showName, !s.name.isEmpty {
            let a = Curve.easeInOut.track(q, [(0.42, 0), (0.46, 1), (0.50, 1), (0.52, 0)])
            layers.append(k.text(s.name, at: ctr, size: 72 * u, color: fg(on: s.ink), alpha: CGFloat(a)))
        }
        return k.stack(layers)
    }
}
