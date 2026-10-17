// Liquid, Ripple, Tunnel and Film burn: the motion stingers, ported from their design boards (see Stinger.swift).
import CoreGraphics
import UIKit

extension StingerArt {
    // MARK: Liquid

    /// (x, y, r, delay) per drop on the board; the goo filter merges them.
    private static let liquidSpec: [(Double, Double, Double, Double)] = [
        (1080, 660, 360, 0), (420, 300, 300, 0.012), (1680, 360, 280, 0.02), (300, 980, 320, 0.03), (1500, 1060, 340, 0.016),
        (820, 1180, 240, 0.04), (2000, 900, 260, 0.026), (640, 640, 220, 0.034), (1360, 140, 220, 0.046),
    ]

    /// Two layers of drops (accent, then ink) that swell to cover the frame and shrink away; merged as a metaball field.
    static func liquid(_ c: CGContext, _ size: CGSize, _ q: Double, _ s: StingerStyle) {
        let curve = Curve(0.65, 0, 0.35, 1)
        goo(c, size, q, curve, [(0.23, 0), (0.38, 1), (0.57, 1), (0.72, 0)], s.accent)
        goo(c, size, q, curve, [(0.25, 0), (0.40, 1), (0.55, 1), (0.70, 0)], s.ink)
        if s.showName && !s.name.isEmpty {
            let u = unit(size)
            let o = Curve(0.33, 1, 0.68, 1)
            let a = o.track(q, [(0.46, 0), (0.49, 1), (0.53, 1), (0.55, 0)])
            let dy = o.track(q, [(0.46, 16), (0.49, 0), (0.53, 0), (0.55, 0)])
            name(s.name, at: CGPoint(x: size.width / 2, y: size.height / 2 + dy * u), size: 56 * u,
                 color: fg(on: s.ink), alpha: a)
        }
    }

    // ponytail: low-res field (about size/6) upscaled by the mask clip; edges are soft like the board's blur.
    private static func goo(_ c: CGContext, _ size: CGSize, _ q: Double, _ curve: Curve, _ stops: [(Double, Double)], _ argb: UInt32) {
        let m = Double(max(size.width, size.height)) / 1920
        // blob centre and squared radius now: the board's scale k = 1500 / r makes every drop 1500 board px at full size
        let blobs: [(x: Double, y: Double, r2: Double)] = liquidSpec.map { spec in
            let (x, y, _, d) = spec
            let r = 1500 * curve.track(q - d, stops) * m
            return ((x - 120) / 1920 * Double(size.width), (y - 120) / 1080 * Double(size.height), r * r)
        }
        guard blobs.contains(where: { $0.r2 > 1e-6 }) else { return }
        let gw = max(1, Int((size.width / 6).rounded())), gh = max(1, Int((size.height / 6).rounded()))
        var buf = [UInt8](repeating: 0, count: gw * gh)
        for row in 0..<gh {
            // CGImage row 0 is the image top, which a flipped (top-left origin) context draws at the bottom: store reversed.
            let cy = (Double(gh - 1 - row) + 0.5) / Double(gh) * Double(size.height)
            for col in 0..<gw {
                let cx = (Double(col) + 0.5) / Double(gw) * Double(size.width)
                var f = 0.0
                for b in blobs where b.r2 > 1e-6 {
                    let dx = cx - b.x, dy = cy - b.y
                    f += b.r2 / max(dx * dx + dy * dy, 1e-6)
                }
                buf[row * gw + col] = UInt8(min(max((f - 0.8) / 0.4, 0), 1) * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(buf) as CFData),
              let mask = CGImage(width: gw, height: gh, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: gw,
                                 space: CGColorSpaceCreateDeviceGray(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
                                 decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return }
        let rect = CGRect(origin: .zero, size: size)
        c.saveGState()
        c.interpolationQuality = .high
        c.clip(to: rect, mask: mask)
        c.setFillColor(color(argb))
        c.fill(rect)
        c.restoreGState()
    }

    // MARK: Ripple

    /// Four rings grow in from the centre (circular clip) and open out again through a growing central hole.
    static func ripple(_ c: CGContext, _ size: CGSize, _ q: Double, _ s: StingerStyle) {
        let curve = Curve(0.65, 0, 0.35, 1)
        let hd = Double(halfDiagonal(size))
        let cen = center(size)
        let colors = [s.accent, mixWhite(s.ink, 0.08), s.accent, s.ink]
        for (i, argb) in colors.enumerated() {
            let pct = curve.track(q - Double(i) * 0.02, [(0.25, 0), (0.40, 80)])
            let rIn = pct / 80 * hd * 1.02
            let hole = curve.track(q - Double(3 - i) * 0.03, [(0.53, 0), (0.68, 1300)]) / 1101 * hd
            guard rIn > 0.5, hole < rIn else { continue }
            let p = CGMutablePath()
            p.addEllipse(in: CGRect(x: cen.x - rIn, y: cen.y - rIn, width: rIn * 2, height: rIn * 2))
            if hole > 0.5 { p.addEllipse(in: CGRect(x: cen.x - hole, y: cen.y - hole, width: hole * 2, height: hole * 2)) }
            c.saveGState()
            c.addPath(p)
            c.setFillColor(color(argb))
            c.fillPath(using: .evenOdd)
            c.restoreGState()
        }
        if s.showName && !s.name.isEmpty {
            let o = Curve(0.33, 1, 0.68, 1)
            name(s.name, at: cen, size: 56 * unit(size), color: fg(on: s.ink),
                 alpha: o.track(q, [(0.44, 0), (0.48, 1), (0.52, 1), (0.54, 0)]),
                 scale: o.track(q, [(0.44, 0.97), (0.48, 1), (0.52, 1), (0.54, 1.02)]))
        }
    }

    // MARK: Tunnel

    /// Five rounded frames fly out of the centre one after another, spinning, then fold back in reverse.
    static func tunnel(_ c: CGContext, _ size: CGSize, _ q: Double, _ s: StingerStyle) {
        let curve = Curve(0.76, 0, 0.24, 1)
        let u = unit(size)
        let cen = center(size)
        let colors = [s.accent, mixWhite(s.ink, 0.12), mixWhite(s.ink, 0.07), mixWhite(s.ink, 0.03), s.ink]
        let w = size.width + 220 * u, h = size.height + 220 * u
        for (i, argb) in colors.enumerated() {
            let qi = q - Double(i) * 0.015, qo = q - Double(4 - i) * 0.03
            let sc = curve.track(qi, [(0.25, 0), (0.41, 1)]) * curve.track(qo, [(0.55, 1), (0.70, 0)])
            let rot = curve.track(qi, [(0.25, -10), (0.41, 0)]) + curve.track(qo, [(0.55, 0), (0.70, 10)])
            guard sc > 0.001 else { continue }
            c.saveGState()
            c.translateBy(x: cen.x, y: cen.y)
            c.rotate(by: CGFloat(rot * .pi / 180))
            c.scaleBy(x: CGFloat(sc), y: CGFloat(sc))
            let p = CGMutablePath()
            p.addRoundedRect(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: 72 * u, cornerHeight: 72 * u)
            c.addPath(p)
            c.setFillColor(color(argb))
            c.fillPath()
            c.restoreGState()
        }
        if s.showName && !s.name.isEmpty {
            let o = Curve(0.33, 1, 0.68, 1)
            name(s.name, at: cen, size: 56 * u, color: fg(on: s.ink),
                 alpha: o.track(q, [(0.47, 0), (0.50, 1), (0.54, 1), (0.56, 0)]),
                 scale: o.track(q, [(0.47, 0.9), (0.50, 1), (0.54, 1), (0.56, 0.9)]))
        }
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
    static func burn(_ c: CGContext, _ size: CGSize, _ q: Double, _ s: StingerStyle) {
        let tone = burnTone(s)
        let curve = Curve(0.45, 0, 0.55, 1)
        let k = CGFloat(halfDiagonal(size)) / 1101
        let cen = center(size)
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        // (colour, clear-at fraction, start, end, from (x, y), to (x, y)) per blob
        let blobs: [(UInt32, Double, Double, Double, (Double, Double), (Double, Double))] = [
            (tone[0], 0.62, 0.25, 0.70, (-2400, -120), (2400, 80)),
            (tone[1], 0.60, 0.28, 0.66, (2400, 260), (-2400, -200)),
            (tone[2], 0.58, 0.30, 0.72, (-2400, 420), (2400, -300)),
        ]
        // ponytail: the board blends these with mix-blend-mode screen against the camera, which an overlay bitmap can't
        // do (the stream composites it with normal alpha), so the blobs read slightly darker over bright video.
        for (argb, clearAt, t0, t1, a, b) in blobs where q > t0 && q < t1 {
            let tx = curve.track(q, [(t0, a.0), (t1, b.0)]), ty = curve.track(q, [(t0, a.1), (t1, b.1)])
            let p = CGPoint(x: cen.x + CGFloat(tx) * k, y: cen.y + CGFloat(ty) * k)
            // CSS "circle" gradients reach the farthest corner of the 2200 px box: 1100 * sqrt(2)
            let r = CGFloat(clearAt * 1100 * 2.0.squareRoot()) * k
            guard let g = CGGradient(colorsSpace: space, colors: [color(argb), color(argb, alpha: 0)] as CFArray, locations: [0, 1])
            else { continue }
            c.saveGState()
            c.setBlendMode(.screen)
            c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
            c.restoreGState()
        }
        let peak = Curve.easeInOut.track(q, [(0.38, 0), (0.45, 1), (0.52, 1), (0.64, 0)])
        if peak > 0.001, let g = CGGradient(colorsSpace: space, colors: [color(0xFFFF_FFFF), color(tone[3])] as CFArray, locations: [0, 1]) {
            c.saveGState()
            c.setAlpha(CGFloat(peak))
            c.drawRadialGradient(g, startCenter: cen, startRadius: 0, endCenter: cen, endRadius: halfDiagonal(size) * 0.7,
                                 options: [.drawsAfterEndLocation])
            c.restoreGState()
        }
        if s.showName && !s.name.isEmpty {
            let o = Curve(0.33, 1, 0.68, 1)
            name(s.name, at: cen, size: 56 * unit(size), color: tone[4],
                 alpha: o.track(q, [(0.455, 0), (0.48, 1), (0.51, 1), (0.53, 0)]),
                 tracking: o.track(q, [(0.455, 0.12), (0.48, -0.01), (0.51, -0.01), (0.53, -0.01)]))
        }
    }
}
