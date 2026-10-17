// Camera-themed stingers: Lens, Aperture blades, Route & pin, Viewfinder. Each reproduces its design board's keyframes.
import CoreGraphics
import UIKit

extension StingerArt {
    // MARK: shared helpers

    /// Board point (1920x1080) mapped around the canvas centre.
    private static func camAt(_ size: CGSize, _ x: Double, _ y: Double) -> CGPoint {
        let u = unit(size), ctr = center(size)
        return CGPoint(x: ctr.x + (x - 960) * u, y: ctr.y + (y - 540) * u)
    }

    private static func camDisc(_ p: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
    }

    private static func camLinear(_ c: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray,
                                 locations: [0, 1]) else { return }
        c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func camRadial(_ c: CGContext, _ colors: [CGColor], _ locs: [CGFloat], at p: CGPoint, radius: CGFloat) {
        guard radius > 0, let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray,
                                             locations: locs) else { return }
        c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [.drawsAfterEndLocation])
    }

    /// Draws `body` as one group at `alpha` (CSS opacity on an element with children).
    private static func camGroup(_ c: CGContext, _ alpha: Double, _ body: () -> Void) {
        guard alpha > 0.001 else { return }
        c.saveGState()
        c.setAlpha(CGFloat(min(alpha, 1)))
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        c.endTransparencyLayer()
        c.restoreGState()
    }

    // MARK: lens

    /// Graphite plate with a hole that shrinks onto the splash's lens (rim, glass, tally, wordmark), then opens again.
    static func lens(_ c: CGContext, _ size: CGSize, _ q: Double, _ s: StingerStyle) {
        guard q > 0.24, q < 0.66 else { return }
        let u = unit(size), ctr = center(size), hd = halfDiagonal(size)
        let bounds = CGRect(origin: .zero, size: size)
        // 1250 board px = "off screen": beyond the corners whatever the canvas shape; 215 scales by unit.
        let big = max(1250 * u, hd + 24)
        let hv = Curve(0.65, 0, 0.35, 1).track(q, [(0.25, 1250), (0.38, 215), (0.55, 215), (0.64, 1250)])
        let hole = 215 * u + CGFloat((hv - 215) / 1035) * (big - 215 * u)

        // Graphite plate everywhere outside the rim's inner edge.
        c.saveGState()
        let plate = CGMutablePath()
        plate.addRect(bounds)
        plate.addEllipse(in: camDisc(ctr, hole - 12 * u))
        c.addPath(plate)
        c.clip(using: .evenOdd)
        camLinear(c, [color(0xFF1C_1C1F), color(0xFF0A_0A0C)], from: .zero, to: CGPoint(x: 0, y: size.height))
        c.restoreGState()

        // Inner graphite disc behind the glass.
        camGroup(c, Curve.easeInOut.track(q, [(0.36, 0), (0.40, 1), (0.52, 1), (0.55, 0)])) {
            c.saveGState()
            c.addEllipse(in: camDisc(ctr, 216 * u))
            c.clip()
            camLinear(c, [color(0xFF1C_1C1F), color(0xFF0A_0A0C)], from: CGPoint(x: 0, y: ctr.y - 216 * u),
                      to: CGPoint(x: 0, y: ctr.y + 216 * u))
            c.restoreGState()
        }

        // Glass: radial dark disc, hairline ring, crescent reflection.
        camGroup(c, Curve.easeInOut.track(q, [(0.37, 0), (0.42, 1), (0.52, 1), (0.55, 0)])) {
            c.saveGState()
            c.addEllipse(in: camDisc(ctr, 203 * u))
            c.clip()
            camRadial(c, [color(0xFF16_181E), color(0xFF02_0203)], [0, 1], at: ctr, radius: 200 * u)
            c.setStrokeColor(color(0xFFFF_FFFF, alpha: 0.07))
            c.setLineWidth(3 * u)
            c.strokeEllipse(in: camDisc(ctr, 137.5 * u))
            // Crescent = circle A minus circle B. ponytail: no 6px blur, drawn crisp at 16%.
            c.saveGState()
            c.addEllipse(in: camDisc(camAt(size, 939, 519), 182 * u))
            c.clip()
            let cres = CGMutablePath()
            cres.addRect(bounds)
            cres.addEllipse(in: camDisc(camAt(size, 959, 553), 182 * u))
            c.addPath(cres)
            c.setFillColor(color(0xFFFF_FFFF, alpha: 0.16))
            c.fillPath(using: .evenOdd)
            c.restoreGState()
            c.restoreGState()
        }

        let pop = Curve(0.33, 1, 0.68, 1)

        // Bloom behind the tally.
        let bloomA = pop.track(q, [(0.39, 0), (0.42, 0.9), (0.46, 0.65), (0.52, 0.65), (0.535, 0)])
        let bloomS = pop.track(q, [(0.39, 1.4), (0.42, 1.9), (0.46, 2.2)])
        if bloomA > 0.001 {
            camGroup(c, bloomA) {
                camRadial(c, [color(s.tally), color(s.tally, alpha: 0)], [0, 1], at: ctr, radius: 42 * u * CGFloat(bloomS))
            }
        }

        // Tally: warm vertical gradient with a soft highlight.
        let tallyA = pop.track(q, [(0.39, 0), (0.44, 1), (0.52, 1), (0.535, 0)])
        let tallyS = CGFloat(pop.track(q, [(0.39, 0.9), (0.44, 1)]))
        camGroup(c, tallyA) {
            let r = 42 * u * tallyS
            let top = s.tally == 0xFFE8_101E ? UInt32(0xFFFF_5A3C) : mixWhite(s.tally, 0.3)
            c.saveGState()
            c.addEllipse(in: camDisc(ctr, r))
            c.clip()
            camLinear(c, [color(top), color(s.tally)], from: CGPoint(x: 0, y: ctr.y - r), to: CGPoint(x: 0, y: ctr.y + r))
            // ponytail: the 5px blurred highlight is a radial falloff instead of a real blur.
            let hl = CGPoint(x: ctr.x, y: ctr.y - 10 * u * tallyS)
            camRadial(c, [color(0xFFFF_FFFF, alpha: 0.28), color(0xFFFF_FFFF, alpha: 0.28), color(0xFFFF_FFFF, alpha: 0)],
                      [0, 0.7, 1], at: hl, radius: 35 * u * tallyS)
            c.restoreGState()
        }

        // Titanium rim, lit from the top-left.
        let rimA = Curve.linear.track(q, [(0.245, 0), (0.27, 1), (0.62, 1), (0.65, 0)])
        if rimA > 0.001, hole - 12 * u < hd + 1 {
            camGroup(c, rimA) {
                let outer = hole + 12 * u
                let ring = CGMutablePath()
                ring.addEllipse(in: camDisc(ctr, outer))
                ring.addEllipse(in: camDisc(ctr, hole - 12 * u))
                c.saveGState()
                c.addPath(ring)
                c.clip(using: .evenOdd)
                camLinear(c, [color(0xFFC8_C8CE), color(0xFF3A_3A3E)], from: CGPoint(x: ctr.x - outer, y: ctr.y - outer),
                          to: CGPoint(x: ctr.x + outer, y: ctr.y + outer))
                c.restoreGState()
            }
        }

        // Wordmark: rises 16px while the tracking tightens 0.32em -> 0.2em.
        if s.showName, !s.name.isEmpty {
            let a = pop.track(q, [(0.41, 0), (0.47, 0.92), (0.52, 0.92), (0.54, 0)])
            let track = pop.track(q, [(0.41, 0.32), (0.47, 0.2)])
            let rise = pop.track(q, [(0.41, 16), (0.47, 0)])
            // Box top is 880; a 52px line is ~62px tall, so its middle sits near 911.
            let at = camAt(size, 960, 911 + rise)
            name(s.name, at: at, size: 52 * u, weight: .regular, color: 0xFFFF_FFFF, alpha: CGFloat(a), tracking: CGFloat(track))
        }
    }

    // MARK: aperture

    /// Six ink blades slide in from outside, close like an iris (spinning 50 degrees), then leave the other way.
    static func aperture(_ c: CGContext, _ size: CGSize, _ q: Double, _ s: StingerStyle) {
        guard q >= 0.25, q <= 0.67 else { return }
        let u = unit(size), ctr = center(size), k = halfDiagonal(size) / 1101
        let blade = Curve(0.76, 0, 0.24, 1)
        let f = blade.track(q, [(0.25, 0), (0.40, 1), (0.52, 1), (0.67, 0)])
        let spin = blade.track(q, [(0.25, -50), (0.40, 0), (0.52, 0), (0.67, 50)])
        let open = -1400 * k, closed = 30 * u
        let ty = open + (closed - open) * CGFloat(f)
        let edgeA = Curve.linear.track(q, [(0.36, 1), (0.40, 0), (0.52, 0), (0.56, 1)])
        let fills = [color(mixWhite(s.ink, 0.05)), color(s.ink)]   // board: even blades a shade lighter

        for i in 0..<6 {
            c.saveGState()
            c.translateBy(x: ctr.x, y: ctr.y)
            c.rotate(by: CGFloat((Double(i) * 60 + spin) * .pi / 180))
            c.translateBy(x: 0, y: ty)
            c.setFillColor(fills[i % 2])
            c.fill(CGRect(x: -2000 * k, y: -3000 * k, width: 4000 * k, height: 3000 * k))
            if edgeA > 0.001 {
                c.setFillColor(color(s.accent, alpha: CGFloat(edgeA)))
                c.fill(CGRect(x: -2000 * k, y: -4 * u, width: 4000 * k, height: 4 * u))
            }
            c.restoreGState()
        }

        if s.showName, !s.name.isEmpty {
            let pop = Curve(0.33, 1, 0.68, 1)
            let a = pop.track(q, [(0.41, 0), (0.45, 1), (0.50, 1), (0.53, 0)])
            let sc = pop.track(q, [(0.41, 0.96), (0.45, 1), (0.50, 1), (0.53, 1.02)])
            name(s.name, at: ctr, size: 56 * u, color: fg(on: s.ink), alpha: CGFloat(a), scale: CGFloat(sc))
        }
    }

    // MARK: route

    /// An accent route draws itself toward the centre, a pin pops there, ink floods out from it, the name rises.
    static func route(_ c: CGContext, _ size: CGSize, _ q: Double, _ s: StingerStyle) {
        guard q >= 0.24, q <= 0.64 else { return }
        let u = unit(size), ctr = center(size), hd = halfDiagonal(size)

        // Route line: sample "M -40 1000 C 360 1000 420 640 760 720 C 1000 776 1080 610 960 540" and stroke a prefix.
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
                    pts.append(camAt(size, x, y))
                }
            }
            var cum: [CGFloat] = [0]
            for i in 1..<pts.count { cum.append(cum[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
            let target = CGFloat(min(frac, 1)) * cum[cum.count - 1]
            let path = CGMutablePath()
            path.move(to: pts[0])
            for i in 1..<pts.count {
                if cum[i] <= target {
                    path.addLine(to: pts[i])
                } else {
                    let seg = cum[i] - cum[i - 1]
                    let r = seg > 0 ? (target - cum[i - 1]) / seg : 0
                    path.addLine(to: CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * r,
                                             y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * r))
                    break
                }
            }
            c.saveGState()
            c.addPath(path)
            c.setStrokeColor(color(s.accent, alpha: CGFloat(lineA)))
            c.setLineWidth(8 * u)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            c.strokePath()
            c.restoreGState()
        }

        // Ink flood: circle(pct) from the centre; 80% = the whole frame.
        let pct = Curve(0.76, 0, 0.24, 1).track(q, [(0.37, 0), (0.46, 80), (0.54, 80), (0.64, 0)])
        let r = CGFloat(pct / 0.8) * hd * 1.02
        if r > 0.5 {
            c.setFillColor(color(s.ink))
            c.fillEllipse(in: camDisc(ctr, r))
        }

        // Pin with an overshoot pop.
        let pop = Curve(0.33, 1, 0.68, 1)
        let ps = CGFloat(pop.track(q, [(0.34, 0), (0.365, 1.25), (0.38, 1), (0.54, 1), (0.62, 0)]))
        if ps > 0.001 {
            c.setFillColor(color(s.accent))
            c.fillEllipse(in: camDisc(ctr, 18 * u * ps))
            c.setFillColor(color(s.ink))
            c.fillEllipse(in: camDisc(ctr, 6 * u * ps))
        }

        // Name below the pin: box top 590, a 44px line is ~53px tall, so its middle sits near 616.
        if s.showName, !s.name.isEmpty {
            let a = pop.track(q, [(0.44, 0), (0.475, 1), (0.51, 1), (0.535, 0)])
            let dy = pop.track(q, [(0.44, 12), (0.475, 0)])
            name(s.name, at: camAt(size, 960, 616 + dy), size: 44 * u, color: fg(on: s.ink), alpha: CGFloat(a))
        }
    }

    // MARK: viewfinder

    /// Ink opens from the centre like a framed shot, accent corner brackets trace it, the name fades in at full frame.
    static func viewfinder(_ c: CGContext, _ size: CGSize, _ q: Double, _ s: StingerStyle) {
        guard q >= 0.25, q <= 0.66 else { return }
        let u = unit(size), ctr = center(size)
        let w = size.width, h = size.height
        let ease = Curve(0.76, 0, 0.24, 1)

        // Ink clip: inset(v% h%) of the canvas.
        let iv = ease.track(q, [(0.25, 50), (0.33, 38), (0.35, 38), (0.42, 0), (0.52, 0), (0.59, 38), (0.61, 38), (0.66, 50)])
        let ih = ease.track(q, [(0.25, 50), (0.33, 34), (0.35, 34), (0.42, 0), (0.52, 0), (0.59, 34), (0.61, 34), (0.66, 50)])
        let ink = CGRect(x: w * CGFloat(ih / 100), y: h * CGFloat(iv / 100), width: w * CGFloat(1 - 2 * ih / 100),
                         height: h * CGFloat(1 - 2 * iv / 100))
        if ink.width > 0.5, ink.height > 0.5 {
            c.setFillColor(color(s.ink))
            c.fill(ink)
        }

        // Corner brackets on an animated inset rect.
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
            let br = CGMutablePath()
            for (x, dx) in [(fr.minX, CGFloat(1)), (fr.maxX, -1)] {
                for (y, dy) in [(fr.minY, CGFloat(1)), (fr.maxY, -1)] {
                    br.addRect(CGRect(x: min(x, x + dx * arm), y: min(y, y + dy * t), width: arm, height: t))
                    br.addRect(CGRect(x: min(x, x + dx * t), y: min(y, y + dy * arm), width: t, height: arm))
                }
            }
            c.addPath(br)
            c.setFillColor(color(s.accent, alpha: CGFloat(fo)))
            c.fillPath()
        }

        if s.showName, !s.name.isEmpty {
            let a = Curve.easeInOut.track(q, [(0.42, 0), (0.46, 1), (0.50, 1), (0.52, 0)])
            name(s.name, at: ctr, size: 72 * u, color: fg(on: s.ink), alpha: CGFloat(a))
        }
    }
}
