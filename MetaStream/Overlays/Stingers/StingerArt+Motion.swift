// Liquid, Ripple, Tunnel and Film burn: the motion stingers, ported from their design boards (see Stinger.swift).
// Core Image recipes (see StingerCanvas): the GPU draws them.
import CoreGraphics
import CoreImage
import UIKit

extension StingerArt {
    // MARK: Liquid

    /// (x, y, r, delay) per drop on the board; the goo filter merges them.
    private static let liquidSpec: [(Double, Double, Double, Double)] = [
        (1080, 660, 360, 0), (420, 300, 300, 0.012), (1680, 360, 280, 0.02), (300, 980, 320, 0.03), (1500, 1060, 340, 0.016),
        (820, 1180, 240, 0.04), (2000, 900, 260, 0.026), (640, 640, 220, 0.034), (1360, 140, 220, 0.046),
    ]

    /// Two layers of drops (accent, then ink) that swell to cover the frame and shrink away; the board's goo filter merges them.
    static func liquid(_ k: StingerCanvas, _ q: Double, _ s: StingerStyle) -> CIImage {
        let curve = Curve(0.65, 0, 0.35, 1)
        var layers = [
            gooLayer(k, q, curve, [(0.23, 0), (0.38, 1), (0.57, 1), (0.72, 0)], s.accent),
            gooLayer(k, q, curve, [(0.25, 0), (0.40, 1), (0.55, 1), (0.70, 0)], s.ink),
        ]
        if s.showName && !s.name.isEmpty {
            let u = k.unit
            let o = Curve(0.33, 1, 0.68, 1)
            let a = o.track(q, [(0.46, 0), (0.49, 1), (0.53, 1), (0.55, 0)])
            let dy = o.track(q, [(0.46, 16), (0.49, 0), (0.53, 0), (0.55, 0)])
            layers.append(k.text(s.name, at: CGPoint(x: k.center.x, y: k.center.y + dy * u), size: 56 * u,
                                 color: fg(on: s.ink), alpha: a))
        }
        return k.stack(layers)
    }

    private static func gooLayer(_ k: StingerCanvas, _ q: Double, _ curve: Curve, _ stops: [(Double, Double)], _ argb: UInt32) -> CIImage {
        let m = max(k.size.width, k.size.height) / 1920
        let limit = k.bounds.insetBy(dx: -200, dy: -200)
        // the board's scale k = 1500 / r makes every drop 1500 board px at full size
        var blobs: [CIImage] = []
        for (x, y, _, d) in liquidSpec {
            let r = 1500 * curve.track(q - d, stops) * Double(m)
            guard r > 0.5 else { continue }
            let c = CGPoint(x: (x - 120) / 1920 * Double(k.size.width), y: (y - 120) / 1080 * Double(k.size.height))
            blobs.append(k.disc(c, CGFloat(r), 0xFFFF_FFFF).cropped(to: limit))
        }
        guard !blobs.isEmpty else { return .empty() }
        return k.goo(k.stack(blobs), sigma: 36 * m, argb)
    }

    // MARK: Ripple

    /// Four rings grow in from the centre (circular clip) and open out again through a growing central hole.
    static func ripple(_ k: StingerCanvas, _ q: Double, _ s: StingerStyle) -> CIImage {
        let curve = Curve(0.65, 0, 0.35, 1)
        let hd = Double(k.halfDiagonal)
        let cen = k.center
        let colors = [s.accent, mixWhite(s.ink, 0.08), s.accent, s.ink]
        var layers: [CIImage] = []
        for (i, argb) in colors.enumerated() {
            let pct = curve.track(q - Double(i) * 0.02, [(0.25, 0), (0.40, 80)])
            let rIn = pct / 80 * hd * 1.02
            let hole = curve.track(q - Double(3 - i) * 0.03, [(0.53, 0), (0.68, 1300)]) / 1101 * hd
            guard rIn > 0.5, hole < rIn else { continue }
            layers.append(k.ring(cen, inner: hole > 0.5 ? CGFloat(hole) : 0, outer: CGFloat(rIn), argb))
        }
        if s.showName && !s.name.isEmpty {
            let o = Curve(0.33, 1, 0.68, 1)
            layers.append(k.text(s.name, at: cen, size: 56 * k.unit, color: fg(on: s.ink),
                                 alpha: o.track(q, [(0.44, 0), (0.48, 1), (0.52, 1), (0.54, 0)]),
                                 scale: o.track(q, [(0.44, 0.97), (0.48, 1), (0.52, 1), (0.54, 1.02)])))
        }
        return k.stack(layers)
    }

    // MARK: Tunnel

    /// Five rounded frames fly out of the centre one after another, spinning, then fold back in reverse.
    static func tunnel(_ k: StingerCanvas, _ q: Double, _ s: StingerStyle) -> CIImage {
        let curve = Curve(0.76, 0, 0.24, 1)
        let u = k.unit
        let cen = k.center
        let colors = [s.accent, mixWhite(s.ink, 0.12), mixWhite(s.ink, 0.07), mixWhite(s.ink, 0.03), s.ink]
        let w = k.size.width + 220 * u, h = k.size.height + 220 * u
        let rect = CGRect(x: cen.x - w / 2, y: cen.y - h / 2, width: w, height: h)
        var layers: [CIImage] = []
        for (i, argb) in colors.enumerated() {
            let qi = q - Double(i) * 0.015, qo = q - Double(4 - i) * 0.03
            let sc = curve.track(qi, [(0.25, 0), (0.41, 1)]) * curve.track(qo, [(0.55, 1), (0.70, 0)])
            let rot = curve.track(qi, [(0.25, -10), (0.41, 0)]) + curve.track(qo, [(0.55, 0), (0.70, 10)])
            guard sc > 0.001 else { continue }
            layers.append(k.transform(k.roundedRect(rect, radius: 72 * u, argb), about: cen, scale: CGFloat(sc), rotate: CGFloat(rot)))
        }
        if s.showName && !s.name.isEmpty {
            let o = Curve(0.33, 1, 0.68, 1)
            layers.append(k.text(s.name, at: cen, size: 56 * u, color: fg(on: s.ink),
                                 alpha: o.track(q, [(0.47, 0), (0.50, 1), (0.54, 1), (0.56, 0)]),
                                 scale: o.track(q, [(0.47, 0.9), (0.50, 1), (0.54, 1), (0.56, 0.9)])))
        }
        return k.stack(layers)
    }

    // MARK: Film burn

    /// Colour, colour, colour, peak and name colour for a tone (the board's tones table).
    private static func burnTone(_ s: StingerStyle) -> [UInt32] {
        switch s.tone {
        case "cool": [0xFF3B_82F6, 0xFF22_D3EE, 0xFFA8_55F7, 0xFFE3_F1FF, 0xFF0B_1A33]
        case "accent": [s.accent, mixWhite(s.accent, 0.4), s.accent, mixWhite(s.accent, 0.85), 0xFF0B_0B0C]
        default: [0xFFFF_5A1F, 0xFFFF_B000, 0xFFFF_2E63, 0xFFFF_E7C7, 0xFF3A_1C08]
        }
    }

    /// Three glowing blobs sweep across, then a white-hot flash peaks at the centre and fades.
    static func burn(_ k: StingerCanvas, _ q: Double, _ s: StingerStyle) -> CIImage {
        let tone = burnTone(s)
        let curve = Curve(0.45, 0, 0.55, 1)
        let kk = k.halfDiagonal / 1101
        let cen = k.center
        // (colour, clear-at fraction, start, end, from (x, y), to (x, y)) per blob
        let blobs: [(UInt32, Double, Double, Double, (Double, Double), (Double, Double))] = [
            (tone[0], 0.62, 0.25, 0.70, (-2400, -120), (2400, 80)),
            (tone[1], 0.60, 0.28, 0.66, (2400, 260), (-2400, -200)),
            (tone[2], 0.58, 0.30, 0.72, (-2400, 420), (2400, -300)),
        ]
        // ponytail: the board blends these with mix-blend-mode screen against the camera, which an overlay bitmap can't
        // do (the stream composites it with normal alpha), so the blobs read slightly darker over bright video.
        var acc: CIImage?
        for (argb, clearAt, t0, t1, a, b) in blobs where q > t0 && q < t1 {
            let tx = curve.track(q, [(t0, a.0), (t1, b.0)]), ty = curve.track(q, [(t0, a.1), (t1, b.1)])
            let p = CGPoint(x: cen.x + CGFloat(tx) * kk, y: cen.y + CGFloat(ty) * kk)
            // CSS "circle" gradients reach the farthest corner of the 2200 px box: 1100 * sqrt(2)
            let r = CGFloat(clearAt * 1100 * 2.0.squareRoot()) * kk
            let blob = k.radial(p, 0, r, argb, argb, alphaA: 1, alphaB: 0)
                .cropped(to: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            acc = acc.map { k.screen(blob, over: $0) } ?? blob
        }
        var layers = [acc ?? .empty()]
        let peak = Curve.easeInOut.track(q, [(0.38, 0), (0.45, 1), (0.52, 1), (0.64, 0)])
        if peak > 0.001 {
            let flash = k.radial(cen, 0, 0.7 * k.halfDiagonal, 0xFFFF_FFFF, tone[3]).cropped(to: k.bounds)
            layers.append(k.opacity(flash, peak))
        }
        if s.showName && !s.name.isEmpty {
            let o = Curve(0.33, 1, 0.68, 1)
            layers.append(k.text(s.name, at: cen, size: 56 * k.unit, color: tone[4],
                                 alpha: o.track(q, [(0.455, 0), (0.48, 1), (0.51, 1), (0.53, 0)]),
                                 tracking: o.track(q, [(0.455, 0.12), (0.48, -0.01), (0.51, -0.01), (0.53, -0.01)])))
        }
        return k.stack(layers)
    }
}
