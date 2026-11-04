// Holo card, Shockwave and Goal surge: the three "impact" donation alerts, ported from their design boards (see
// DonationAlert.swift). Core Image recipes (see StingerCanvas): every frame is a pure function of `p`.
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

extension DonationArt {
    private static let impWhite: UInt32 = 0xFFFF_FFFF

    // MARK: shared helpers

    /// `s` hugging the left (-1), centre (0) or right (1) of `x`, centred on `y`; shrunk about that anchor to fit `maxW` (canvas px).
    private static func impText(_ k: StingerCanvas, _ s: String, x: CGFloat, y: CGFloat, align: Int = 0, size: CGFloat,
                                weight: UIFont.Weight, color: UInt32, tracking: CGFloat = 0, face: String = "Manrope",
                                maxW: CGFloat = .infinity) -> CIImage {
        let t = k.text(s, at: .zero, size: size, weight: weight, color: color, tracking: tracking, face: face)
        let e = t.extent
        guard !e.isInfinite, !e.isEmpty else { return .empty() }
        let edge = align < 0 ? e.minX : (align > 0 ? e.maxX : e.midX)
        let moved = t.transformed(by: CGAffineTransform(translationX: x - edge, y: y - e.midY))
        return e.width > maxW ? k.transform(moved, about: CGPoint(x: x, y: y), scale: maxW / e.width) : moved
    }

    private static func impWidth(_ k: StingerCanvas, _ s: String, size: CGFloat, weight: UIFont.Weight, tracking: CGFloat = 0) -> CGFloat {
        let e = k.text(s, at: .zero, size: size, weight: weight, color: impWhite, tracking: tracking, face: "Manrope").extent
        return e.isInfinite || e.isEmpty ? 0 : e.width
    }

    private static func impAccent(_ style: DonationAlertStyle, _ fallback: UInt32) -> UInt32 {
        style.accent == 0 ? fallback : 0xFF00_0000 | style.accent
    }

    /// A 4-point sparkle: two thin crossed diamonds, `half` long, turned by `rot` radians.
    private static func impStar(_ k: StingerCanvas, _ c: CGPoint, half: CGFloat, rot: CGFloat, alpha: CGFloat) -> CIImage {
        guard half > 0.5, alpha > 0.01 else { return .empty() }
        let r = half / 2.0.squareRoot()
        let square = k.fill(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), impWhite, alpha: alpha)
        func arm(_ extra: CGFloat) -> CIImage {
            square.transformed(by: CGAffineTransform(translationX: c.x, y: c.y).rotated(by: rot + extra).scaledBy(x: 0.17, y: 1)
                .rotated(by: .pi / 4).translatedBy(x: -c.x, y: -c.y))
        }
        return arm(0).composited(over: arm(.pi / 2))
    }

    // MARK: Holo card

    /// Rainbow bands (the board's repeating 115deg gradient: five 6% bands per 30% period), tiled and turned 25 degrees.
    /// Lazy GPU graph; nothing is rendered until the frame is.
    private static func impFoil(_ k: StingerCanvas, _ b: DonationBoard, p: Double, at c: CGPoint) -> CIImage {
        let cols: [UInt32] = [0xFFFF_6AD5, 0xFFFF_D36B, 0xFF6B_FFB8, 0xFF6B_C8FF, 0xFFB4_6BFF]
        let band = b.len(71.6)
        let strip = k.stack(cols.enumerated().map { k.fill(CGRect(x: CGFloat($0.offset) * band, y: 0, width: band, height: 64), $0.element) })
        let tile = CIFilter.affineTile()
        tile.inputImage = strip
        tile.transform = .identity
        let endless = tile.outputImage ?? strip
        let shift = -CGFloat(p) * 27.5 * band   // the board slides 300% of a 300%-wide background: ~5.5 periods per loop
        return endless.transformed(by: CGAffineTransform(translationX: c.x, y: c.y).rotated(by: 25 * CGFloat.pi / 180)
            .translatedBy(x: shift, y: -32))
    }

    static func holo(p: Double, info: DonationAlertInfo, style: DonationAlertStyle, c: StingerCanvas, b: DonationBoard) -> CIImage {
        let k = c
        let tiers: [UInt32] = [0xFF6B_9BFF, 0xFFC4_6BFF, 0xFFF5_C542]
        let tier = min(2, max(0, info.tier))
        let acc = impAccent(style, tiers[tier])
        let flip = Curve(0.2, 0.8, 0.25, 1)
        let ry = flip.track(p, [(0, 540), (0.12, -14), (0.17, 6), (0.21, 0), (0.5, -10), (0.8, 0), (0.92, 90)])
        let alpha = flip.track(p, [(0, 0), (0.12, 1), (0.8, 1), (0.92, 0)])
        let tx = flip.track(p, [(0, -520), (0.12, 0)])
        let rz = flip.track(p, [(0, -8), (0.12, 0)])
        let ty = flip.track(p, [(0.8, 0), (0.92, 40)])
        let sc = flip.track(p, [(0.8, 1), (0.92, 0.9)])
        var layers: [CIImage] = []

        // six sparkles twinkling around the card (they sit behind it)
        let spots: [(CGFloat, CGFloat)] = [(-20, 30), (330, -16), (372, 220), (-34, 300), (300, 470), (150, -30)]
        let ease = Curve.easeInOut
        for (i, s) in spots.enumerated() {
            let q = p - Double(i) * 0.18 * style.speed / 7
            guard q > 0.18 else { continue }
            let sz = ease.track(q, [(0.18, 0), (0.24, 1.2), (0.32, 0.4), (0.46, 0), (0.52, 1), (0.60, 0)])
            let a = ease.track(q, [(0.18, 0), (0.24, 1), (0.32, 0), (0.46, 0), (0.52, 1), (0.60, 0)])
            let rot = ease.track(q, [(0.18, 0), (0.24, 45), (0.32, 90), (0.46, 90), (0.52, 45), (0.60, 90)])
            layers.append(impStar(k, b.pt(120 + s.0 + 15, 100 + s.1 + 15), half: b.len(15 * CGFloat(sz)), rot: CGFloat(rot) * .pi / 180,
                                  alpha: CGFloat(min(1, max(0, a)))))
        }

        // the card: horizontal squash = |cos| of the flip angle about its centre, plus the slide and settle
        let cosA = CGFloat(cos(ry * .pi / 180))
        let sx = abs(cosA)
        if alpha > 0.01, sx > 0.004 {
            let cardR = b.rect(120, 100, 360, 510)
            let inner = b.rect(122, 102, 356, 506)
            let rim = k.roundedRect(cardR, radius: b.len(24), acc)
            let face: CIImage
            if cosA >= 0 {
                let shape = k.roundedRect(inner, radius: b.len(22), impWhite)
                let base = k.roundedRect(inner, radius: b.len(22), 0xFF0C_0D11)
                let dodged = impFoil(k, b, p: p, at: b.pt(300, 355)).cropped(to: inner)
                    .applyingFilter("CIColorDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: base])
                let foil = k.opacity(k.clip(dodged, to: shape), 0.32)
                // glare: a white bar sweeping across (the board's translateX in bar widths, 70 px each)
                let gx = Curve.easeInOut.track(p, [(0, -140), (0.20, -140), (0.34, 224), (0.55, -140), (0.68, 224), (1, 224)])
                let gc = b.pt(120 + gx + 35, 355)
                let bar = k.fill(CGRect(x: gc.x - b.len(35), y: gc.y - b.len(408), width: b.len(70), height: b.len(816)), impWhite, alpha: 0.28)
                let glare = k.clip(k.transform(bar, about: gc, rotate: 25), to: shape)
                let left = b.pt(144, 0).x, right = b.pt(456, 0).x
                let hash = info.name.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 9973 }
                let number = String(format: "No. %04d", Int32(hash % 999 + 1))
                let msg = String(info.message.prefix(60))
                let texts: [CIImage] = [
                    impText(k, ["RARE", "EPIC", "LEGENDARY"][tier], x: left, y: b.pt(0, 134).y, align: -1, size: b.len(15), weight: .heavy,
                            color: acc, tracking: 0.18, face: "Unbounded"),
                    impText(k, number, x: right, y: b.pt(0, 134).y, align: 1, size: b.len(14), weight: .bold, color: 0xFF9A_9CA6),
                    k.text(info.initial.uppercased(), at: b.pt(300, 258), size: b.len(64), weight: .heavy, color: acc, face: "Unbounded"),
                    impText(k, info.name.uppercased(), x: left, y: b.pt(0, 393).y, align: -1, size: b.len(34), weight: .heavy,
                            color: impWhite, face: "Unbounded", maxW: right - left),
                    impText(k, info.amount, x: left, y: b.pt(0, 451).y, align: -1, size: b.len(46), weight: .heavy, color: acc,
                            face: "Unbounded", maxW: right - left),
                    impText(k, msg, x: left, y: b.pt(0, 500).y, align: -1, size: b.len(18), weight: .medium, color: 0xFFC8_C9D0,
                            maxW: right - left),
                    impText(k, info.source, x: left, y: b.pt(0, 577).y, align: -1, size: b.len(13), weight: .bold, color: 0xFF8B_8D96,
                            tracking: 0.14),
                    impText(k, info.date, x: right, y: b.pt(0, 577).y, align: 1, size: b.len(13), weight: .bold, color: 0xFF8B_8D96,
                            tracking: 0.14),
                ]
                face = k.stack([rim, base, foil, glare,
                                k.roundedRect(b.rect(144, 158, 312, 200), radius: b.len(16), 0xFF17_181D),
                                k.ring(b.pt(300, 258), inner: b.len(63), outer: b.len(66), acc)] + texts)
            } else {
                face = k.stack([rim, k.ring(b.pt(300, 355), inner: b.len(65), outer: b.len(75), 0xFF0C_0D11)])
            }
            let cc = b.pt(300, 355)
            let rad = CGFloat(rz) * .pi / 180
            let t = CGAffineTransform(translationX: cc.x + b.len(CGFloat(tx)), y: cc.y + b.len(CGFloat(ty)))
                .scaledBy(x: sx * CGFloat(sc), y: CGFloat(sc)).rotated(by: rad).translatedBy(x: -cc.x, y: -cc.y)
            layers.append(k.opacity(face.transformed(by: t), alpha))
        }
        return k.stack(layers)
    }

    // MARK: Shockwave

    private nonisolated(unsafe) static var impRaysCache: [Int: CIImage] = [:]
    private static let impRaysLock = NSLock()

    /// 24 white wedges (3 degrees on, 12 off) under the board's radial mask (clear to 18%, full at 34%, clear at 70%
    /// of the farthest-corner radius). Drawn once per size on the CPU; the frame only moves and tints it.
    private static func impRays(side: CGFloat) -> CIImage {
        let n = max(64, Int(side.rounded()))
        impRaysLock.lock()
        defer { impRaysLock.unlock() }
        if let hit = impRaysCache[n] { return hit }
        let px = CGFloat(n)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let cg = UIGraphicsImageRenderer(size: CGSize(width: n, height: n), format: fmt).image { r in
            let g = r.cgContext
            let mid = CGPoint(x: px / 2, y: px / 2)
            g.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            for i in 0..<24 {
                let a0 = CGFloat(i) * 15 * CGFloat.pi / 180
                g.move(to: mid)
                g.addArc(center: mid, radius: px, startAngle: a0, endAngle: a0 + 3 * CGFloat.pi / 180, clockwise: false)
                g.closePath()
            }
            g.fillPath()
            let stops: [CGFloat] = [0, 0.18, 0.34, 0.70, 1]
            let cols = [0, 0, 1, 0, 0].map { CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat($0)) }
            if let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cols as CFArray, locations: stops) {
                g.setBlendMode(.destinationIn)
                g.drawRadialGradient(grad, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: px / 2 * 2.0.squareRoot(),
                                     options: [.drawsAfterEndLocation])
            }
        }.cgImage
        // into top-left space like everything else; extent (0, 0, side, side)
        let img = cg.map { CIImage(cgImage: $0).transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: px)) } ?? .empty()
        impRaysCache[n] = img
        return img
    }

    static func shockwave(p: Double, info: DonationAlertInfo, style: DonationAlertStyle, c: StingerCanvas, b: DonationBoard) -> CIImage {
        let k = c
        let acc = impAccent(style, 0xFFFF_5A36)
        let lin = Curve.linear
        let out = Curve(0, 0, 0.58, 1)
        var g: [CIImage] = []

        // rays: slowly turning wedges
        let ro = lin.track(p, [(0.03, 0), (0.08, 0.55), (0.84, 0.4), (0.92, 0)])
        if ro > 0.001 {
            let side = b.len(1000)
            let rc = b.pt(640, 220)
            let mask = impRays(side: side).transformed(by: CGAffineTransform(translationX: rc.x - side / 2, y: rc.y - side / 2))
            let tinted = k.clip(k.fill(mask.extent, acc), to: mask)
            let rs = lin.track(p, [(0.03, 0.6), (0.08, 1), (0.84, 1.05), (0.92, 1.3)])
            let rr = lin.track(p, [(0.03, 0), (0.08, 8), (0.84, 40), (0.92, 46)])
            g.append(k.opacity(k.transform(tinted, about: rc, scale: CGFloat(rs), rotate: CGFloat(rr)), ro))
        }

        // three rings expanding with stagger (the border scales with the ring)
        let ringCurve = Curve(0.1, 0.7, 0.3, 1)
        let rc0 = b.pt(640, 280)
        for i in 0..<3 {
            let q = p - [0.0, 0.12, 0.26][i] * style.speed / 7
            guard q > 0.03 else { continue }
            let a = ringCurve.track(q, [(0.03, 0), (0.04, 1), (0.30, 0)])
            let s = ringCurve.track(q, [(0.03, 0.15), (0.30, 5.5)])
            let bw = CGFloat(10 - i * 3)
            g.append(k.ring(rc0, inner: b.len((100 - bw) * CGFloat(s)), outer: b.len(100 * CGFloat(s)), acc, alpha: CGFloat(a)))
        }

        g.append(k.text("NEW TOP DONATION", at: b.pt(640, 122.5), size: b.len(18), weight: .bold, color: acc, tracking: 0.3, face: "Manrope"))

        // name: letters tighten from .9em to .32em (a few cached steps)
        let track = Curve(0.2, 0.8, 0.2, 1)
        let na = track.track(p, [(0.06, 0), (0.16, 1)])
        if na > 0.001 {
            let tr = (track.track(p, [(0.06, 0.9), (0.16, 0.32)]) / 0.04).rounded() * 0.04
            g.append(k.opacity(impText(k, info.name.uppercased(), x: b.pt(640, 0).x, y: b.pt(0, 178).y, size: b.len(40), weight: .semibold,
                                       color: impWhite, tracking: CGFloat(tr), face: "Unbounded", maxW: b.len(1100)), na))
        }

        // amount: slams in from 3.4x with blur, a hard accent shadow under it
        let slam = Curve(0.3, 1.4, 0.5, 1)
        let aa = min(1, max(0, slam.track(p, [(0.025, 0), (0.06, 1)])))
        if aa > 0.001 {
            let ac = b.pt(640, 296)
            let top = impText(k, info.amount, x: ac.x, y: ac.y, size: b.len(150), weight: .black, color: impWhite, face: "Unbounded", maxW: b.len(1100))
            let shadow = impText(k, info.amount, x: ac.x, y: ac.y + b.len(6), size: b.len(150), weight: .black, color: acc, face: "Unbounded",
                                 maxW: b.len(1100))
            let sharp = top.composited(over: shadow)
            let blurred = k.blur(sharp, b.len(CGFloat(max(0, slam.track(p, [(0.025, 16), (0.06, 0)])))))
            let sc = slam.track(p, [(0.025, 3.4), (0.06, 0.92), (0.085, 1)])
            g.append(k.opacity(k.transform(blurred, about: ac, scale: CGFloat(sc)), aa))
        }

        // message fades up
        let ma = out.track(p, [(0.14, 0), (0.22, 1)])
        if ma > 0.001, !info.message.isEmpty {
            let dy = b.len(CGFloat(out.track(p, [(0.14, 16), (0.22, 0)])))
            g.append(k.opacity(impText(k, String(info.message.prefix(100)), x: b.pt(640, 0).x, y: b.pt(0, 407).y + dy, size: b.len(26),
                                       weight: .medium, color: 0xFFD4_D5DC, maxW: b.len(760)), ma))
        }

        // zoom-away exit (ease-in): scale, blur and fade about the board centre
        let ein = Curve(0.42, 0, 1, 1)
        let eo = ein.track(p, [(0.84, 1), (0.93, 0)])
        var scene = k.stack(g)
        if eo < 0.999 {
            let eb = b.len(CGFloat(ein.track(p, [(0.84, 0), (0.93, 10)])))
            scene = k.opacity(k.transform(k.blur(scene, eb), about: b.pt(640, 360), scale: CGFloat(ein.track(p, [(0.84, 1), (0.93, 1.35)]))), eo)
        }

        // the whole picture shakes (not the flash)
        let dx = lin.track(p, [(0.03, 0), (0.04, -14), (0.05, 12), (0.06, -9), (0.07, 8), (0.08, -4), (0.095, 0)])
        let dy = lin.track(p, [(0.03, 0), (0.04, 8), (0.05, -10), (0.06, -6), (0.07, 7), (0.08, 3), (0.095, 0)])
        let shaken = scene.transformed(by: CGAffineTransform(translationX: b.len(CGFloat(dx)), y: b.len(CGFloat(dy))))

        let fl = out.track(p, [(0.02, 0), (0.03, 0.85), (0.09, 0)])
        return k.stack([shaken, k.opacity(k.fill(c.bounds, impWhite), fl)])
    }

    // MARK: Goal surge

    private static func impBezier(_ t: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }

    /// The goal bar laid out in the board's 720x120 box coordinates, mapped to canvas by origin `o` and scale `f`.
    private static func impGoalBox(_ k: StingerCanvas, _ p: Double, _ goal: DonationAlertInfo.Goal, _ acc: UInt32, o: CGPoint, f: CGFloat) -> CIImage {
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * f, y: o.y + y * f) }
        func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: o.x + x * f, y: o.y + y * f, width: w * f, height: h * f) }
        let out = Curve(0, 0, 0.58, 1)
        let glow = out.track(p, [(0.49, 0), (0.52, 1), (0.68, 0)])
        let box = R(0, 0, 720, 120)
        var layers: [CIImage] = []
        if glow > 0.01 {
            let halo = k.stack([k.blur(k.roundedRect(box, radius: 14 * f, acc, alpha: CGFloat(glow)), 24 * f),
                                k.roundedRect(box.insetBy(dx: -3 * f, dy: -3 * f), radius: 17 * f, acc, alpha: CGFloat(glow))])
            layers.append(k.minus(halo, k.roundedRect(box, radius: 14 * f, impWhite)))
        }
        layers.append(k.roundedRect(box, radius: 14 * f, 0xFF10_1014, alpha: 0.85))

        // header: title left, "before / target" right with the number crossfading to "after"
        let rx = P(704, 0).x, rowY = P(0, 33).y
        let target = "/ " + goal.target
        let numRight = rx - impWidth(k, target, size: 28 * f, weight: .heavy) - 10 * f
        let titleMax = numRight - 76 * f - 12 * f - P(16, 0).x
        let oldA = Curve.linear.track(p, [(0.50, 1), (0.51, 0), (0.96, 0), (0.98, 1)])
        let pop = Curve(0.2, 0.9, 0.3, 1.3)
        let newA = min(1, max(0, pop.track(p, [(0.50, 0), (0.54, 1), (0.95, 1), (0.97, 0)])))
        let newDy = CGFloat(pop.track(p, [(0.50, 14), (0.54, 0)])) * f
        layers.append(impText(k, goal.title, x: P(16, 0).x, y: rowY, align: -1, size: 28 * f, weight: .heavy, color: impWhite, maxW: titleMax))
        layers.append(impText(k, target, x: rx, y: rowY, align: 1, size: 28 * f, weight: .heavy, color: impWhite))
        layers.append(k.opacity(impText(k, goal.before, x: numRight, y: rowY, align: 1, size: 28 * f, weight: .heavy, color: impWhite), oldA))
        layers.append(k.opacity(impText(k, goal.after, x: numRight, y: rowY + newDy, align: 1, size: 28 * f, weight: .heavy, color: impWhite), newA))
        let from = min(1, max(0, goal.from)), to = min(1, max(0, goal.to))
        let pctY = P(0, 96.5).y
        layers.append(k.opacity(impText(k, "\(Int((from * 100).rounded()))%", x: rx, y: pctY, align: 1, size: 20 * f, weight: .semibold,
                                        color: 0xD9FF_FFFF), oldA))
        layers.append(k.opacity(impText(k, "\(Int((to * 100).rounded()))%", x: rx, y: pctY + newDy, align: 1, size: 20 * f, weight: .semibold,
                                        color: 0xD9FF_FFFF), newA))

        // bar: track, accent fill growing from `from` to `to`, a white glint running through it
        layers.append(k.roundedRect(R(16, 58, 688, 17), radius: 9 * f, 0xFF26_262B))
        let w = Curve(0.2, 0.8, 0.2, 1).track(p, [(0.50, from), (0.58, to), (0.95, to), (0.99, from)])
        let fillR = R(16, 58, 688 * CGFloat(w), 17)
        if fillR.width > 0.5 {
            let fillShape = k.roundedRect(fillR, radius: 9 * f, acc)
            layers.append(fillShape)
            let ga = out.track(p, [(0.50, 0), (0.52, 1), (0.66, 0)])
            if ga > 0.01 {
                let gx = fillR.minX + CGFloat(out.track(p, [(0.50, -0.2), (0.66, 1.1)])) * fillR.width
                layers.append(k.clip(k.fill(CGRect(x: gx, y: fillR.minY, width: 60 * f, height: fillR.height), impWhite, alpha: 0.7 * CGFloat(ga)),
                                     to: fillShape))
            }
        }
        return k.transform(k.stack(layers), about: P(360, 60), scale: 1 + 0.03 * CGFloat(glow))
    }

    static func goalSurge(p: Double, info: DonationAlertInfo, style: DonationAlertStyle, c: StingerCanvas, b: DonationBoard) -> CIImage {
        let k = c
        let acc = impAccent(style, 0xFF53_FC18)
        let out = Curve(0, 0, 0.58, 1)
        var layers: [CIImage] = []

        // where the orb lands: the end of the new fill, or a top-centre spot without a goal
        // (the bar uses the plain board: only the chip and the orb's start follow the Alerts widget)
        let ub = DonationBoard(c.size)
        var target = ub.pt(640, 100)
        if let goal = info.goal {
            let box = goal.box ?? ub.rect(280, 40, 720, 120)
            let f = box.width / 720
            let o = CGPoint(x: box.minX, y: box.midY - 60 * f)
            target = CGPoint(x: o.x + (16 + 688 * CGFloat(min(1, max(0, goal.to)))) * f, y: o.y + 66.5 * f)
            layers.append(impGoalBox(k, p, goal, acc, o: o, f: f))
        }

        // impact: ring and ten particles
        let ringA = out.track(p, [(0.49, 0), (0.51, 1), (0.64, 0)])
        if ringA > 0.01 {
            let s = CGFloat(out.track(p, [(0.49, 0.3), (0.64, 3.2)]))
            layers.append(k.ring(target, inner: b.len(16 * s), outer: b.len(20 * s), acc, alpha: CGFloat(ringA)))
        }
        let bitA = out.track(p, [(0.49, 0), (0.51, 1), (0.66, 0)])
        if bitA > 0.01 {
            let d = CGFloat(out.track(p, [(0.49, 0), (0.66, 1)]))
            for i in 0..<10 {
                let a = CGFloat(i) / 10 * 2 * CGFloat.pi
                layers.append(k.disc(CGPoint(x: target.x + cos(a) * b.len(90) * d, y: target.y + sin(a) * b.len(60) * d), b.len(4), acc,
                                     alpha: CGFloat(bitA)))
            }
        }

        // the orb and three trailing ones fly the Bezier from the chip to the target
        let fly = Curve(0.5, 0, 0.4, 1)
        let p0 = b.pt(230, 600), p1 = b.pt(170, 340), p2 = b.pt(540, 330)
        let sizes: [CGFloat] = [30, 20, 14, 9]
        let fade: [CGFloat] = [1, 0.55, 0.4, 0.25]
        for i in 0..<4 {
            let q = p - Double(i) * 0.05 * style.speed / 6
            let op = fly.track(q, [(0.31, 0), (0.33, 1), (0.50, 1), (0.51, 0)])
            guard op > 0.01 else { continue }
            let pos = impBezier(CGFloat(fly(Key.span(q, 0.33, 0.50))), p0, p1, p2, target)
            let r = b.len(sizes[i]) / 2
            let reach = r + b.len(sizes[i] * 1.4) * 0.8
            let a = CGFloat(op) * fade[i]
            layers.append(k.radial(pos, r * 0.5, reach, acc, acc, alphaA: a * 0.6, alphaB: 0)
                .cropped(to: CGRect(x: pos.x - reach, y: pos.y - reach, width: 2 * reach, height: 2 * reach)))
            layers.append(k.disc(pos, r, acc, alpha: a))
        }

        // the chip pops at bottom-left and shrinks into the orb
        let pop = Curve(0.2, 0.9, 0.3, 1.2)
        let ca = min(1, max(0, pop.track(p, [(0.03, 0), (0.08, 1), (0.27, 1), (0.33, 0)])))
        let cs = max(0, pop.track(p, [(0.03, 0.5), (0.08, 1.05), (0.11, 1), (0.27, 1), (0.33, 0.08)]))
        if ca > 0.01, cs > 0.005 {
            let cc = b.pt(230, 600)
            let inkC: UInt32 = 0xFF0B_0C0F
            let textMax = b.len(190)
            let chip = k.stack([
                k.roundedRect(b.rect(80, 560, 300, 80), radius: b.len(40), acc),
                k.roundedRect(b.rect(82, 562, 296, 76), radius: b.len(38), inkC),
                k.disc(b.pt(122, 600), b.len(30), acc),
                k.text(info.initial.uppercased(), at: b.pt(122, 600), size: b.len(26), weight: .heavy, color: inkC, tracking: 0, face: "Manrope"),
                impText(k, info.name, x: b.pt(166, 0).x, y: b.pt(0, 585).y, align: -1, size: b.len(16), weight: .semibold, color: 0xFFB9_BAC2,
                        maxW: textMax),
                impText(k, "+" + info.amount, x: b.pt(166, 0).x, y: b.pt(0, 611).y, align: -1, size: b.len(30), weight: .heavy, color: impWhite,
                        maxW: textMax),
            ])
            let dy = b.len(CGFloat(pop.track(p, [(0.03, 30), (0.08, 0)])) * CGFloat(cs))
            layers.append(k.opacity(k.transform(chip, about: cc, scale: CGFloat(cs)).transformed(by: CGAffineTransform(translationX: 0, y: dy)), ca))
        }
        return k.stack(layers)
    }
}
