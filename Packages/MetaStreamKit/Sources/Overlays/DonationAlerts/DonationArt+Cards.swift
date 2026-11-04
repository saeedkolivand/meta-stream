// Coin burst, Neon sign and Receipt donation alerts, ported from their design boards (see DonationAlert.swift).
// Core Image recipes (see StingerCanvas): everything is a pure function of `p`; text is cached by the canvas and the two
// small bitmaps (receipt zigzag, barcode) are cached here, so a frame is only GPU work.
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

extension DonationArt {
    private static let cdWhite: UInt32 = 0xFFFF_FFFF
    private static let cdEaseOut = Curve(0, 0, 0.58, 1)   // CSS ease-out

    /// Width of a text picture (0 for an empty one).
    private static func cdW(_ i: CIImage) -> CGFloat {
        let e = i.extent
        return e.isInfinite || e.isNull ? 0 : e.width
    }

    /// Blur at a reduced size (a big sigma at full size is slow); `sigma` in canvas px.
    private static func cdSoft(_ c: StingerCanvas, _ img: CIImage, _ sigma: CGFloat) -> CIImage {
        let k: CGFloat = sigma >= 40 ? 0.125 : sigma >= 15 ? 0.25 : 0.5
        return c.blur(img.transformed(by: CGAffineTransform(scaleX: k, y: k)), sigma * k)
            .transformed(by: CGAffineTransform(scaleX: 1 / k, y: 1 / k))
    }

    /// Small CPU bitmaps drawn once per size, in top-left space at the origin.
    nonisolated(unsafe) private static var cdBitmaps: [String: CIImage] = [:]

    private static func cdBitmap(_ key: String, _ size: CGSize, _ draw: (CGContext) -> Void) -> CIImage {
        if let hit = cdBitmaps[key] { return hit }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let px = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard let cg = UIGraphicsImageRenderer(size: px, format: fmt).image(actions: { draw($0.cgContext) }).cgImage else { return .empty() }
        let img = CIImage(cgImage: cg).transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: px.height))
        if cdBitmaps.count > 16 { cdBitmaps.removeAll() }
        cdBitmaps[key] = img
        return img
    }

    /// Greedy word wrap by character count (the receipt font is monospaced), long words cut, `…` when over `maxLines`.
    private static func cdWrap(_ s: String, _ n: Int, _ maxLines: Int) -> [String] {
        var lines: [String] = [], cur = ""
        for w in s.split(separator: " ") {
            var word = String(w)
            while word.count > n {
                if !cur.isEmpty { lines.append(cur); cur = "" }
                lines.append(String(word.prefix(n)))
                word = String(word.dropFirst(n))
            }
            if cur.isEmpty { cur = word } else if cur.count + 1 + word.count <= n { cur += " " + word } else { lines.append(cur); cur = word }
        }
        if !cur.isEmpty { lines.append(cur) }
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            lines[maxLines - 1] = String(lines[maxLines - 1].prefix(n - 1)) + "…"
        }
        return lines
    }

    // MARK: coin burst

    /// A dark card pops in with a ring pulse and 18 coins flying out; the amount's digits roll up like an odometer.
    static func coinBurst(p: Double, info: DonationAlertInfo, style: DonationAlertStyle, c: StingerCanvas, b: DonationBoard) -> CIImage {
        guard p < 0.93 else { return .empty() }
        let acc: UInt32 = style.accent == 0 ? 0xFFF5_C542 : style.accent | 0xFF00_0000
        let ink: UInt32 = 0xFF0B_0C0F
        let L = b.len
        let dur = 6 / max(style.speed, 0.1)   // seconds of the whole alert

        // Content sizes first: the card is as wide as its widest line.
        let label = c.text("\(String(info.name.uppercased().prefix(24))) DONATED", at: .zero, size: L(18), weight: .bold, color: acc,
                           tracking: 0.2, face: "Manrope")
        let labelW = cdW(label)
        let hasMsg = !info.message.isEmpty
        let msgImg = hasMsg ? c.text(info.message, at: .zero, size: L(22), weight: .medium, color: 0xFFC8_C9D0, tracking: 0, face: "Manrope") : .empty()
        let msgScale = min(1, L(760) / max(cdW(msgImg), 1))
        let msgW = cdW(msgImg) * msgScale
        let digitW = cdW(c.text("0", at: .zero, size: L(76), weight: .heavy, color: cdWhite, tracking: 0, face: "Unbounded"))
        let chars = Array(info.amount)
        let widths: [CGFloat] = chars.map { ch in
            ch >= "0" && ch <= "9" ? digitW : cdW(c.text(String(ch), at: .zero, size: L(76), weight: .heavy, color: cdWhite, tracking: 0, face: "Unbounded"))
        }
        let amtW = widths.reduce(0, +)

        let colW = max(labelW, amtW, msgW)
        let cardW = L(26 + 92 + 26 + 44) + colW
        let colH = L(25 + 6 + 76) + (hasMsg ? L(6 + 30) : 0)
        let inner = max(L(92), colH)
        let cardH = L(52) + inner
        let top = b.pt(0, 84).y
        let left = b.pt(640, 0).x - cardW / 2
        let card = CGRect(x: left, y: top, width: cardW, height: cardH)
        let mid = CGPoint(x: card.midX, y: card.midY)
        let colX = left + L(144)
        let colTop = top + L(26) + (inner - colH) / 2
        var layers: [CIImage] = []

        // Ring pulse around the card (not part of the pop).
        let ra = cdEaseOut.track(p, [(0.06, 0), (0.08, 0.9), (0.26, 0)])
        if ra > 0.005 {
            let rs = CGFloat(cdEaseOut.track(p, [(0.06, 0.6), (0.26, 1.9)]))
            let base = card.insetBy(dx: -L(18), dy: -L(18))
            let r = CGRect(x: mid.x - base.width * rs / 2, y: mid.y - base.height * rs / 2, width: base.width * rs, height: base.height * rs)
            let w = L(3) * rs
            let rr = L(44) * rs
            layers.append(c.opacity(c.minus(c.roundedRect(r, radius: rr, acc), c.roundedRect(r.insetBy(dx: w, dy: w), radius: rr - w, cdWhite)), ra))
        }

        // Coins: out from the card's centre on an ellipse, shrinking back to nothing.
        let burst = Curve(0.1, 0.8, 0.3, 1)
        for i in 0..<18 {
            let a = Double(i) / 18 * 2 * .pi + 0.2
            let r = 260 + Double(i % 3) * 80
            let pp = p - Double(i % 4) * 0.03 / dur
            let al = burst.track(pp, [(0.05, 0), (0.07, 1), (0.32, 0)])
            guard al > 0.01 else { continue }
            let e = burst.track(pp, [(0.05, 0), (0.32, 1)])
            let ctr = CGPoint(x: mid.x + L(CGFloat(cos(a) * r * e)), y: mid.y + L(CGFloat(sin(a) * r * 0.6 * e)))
            let rad = L(14) * CGFloat(0.3 + 0.7 * e)
            layers.append(c.disc(ctr, rad, acc, alpha: CGFloat(al)))
            layers.append(c.ring(ctr, inner: rad * 9 / 14, outer: rad, 0xFF00_0000, alpha: CGFloat(al) * 0.22))
        }

        // The card.
        let shape = c.roundedRect(card, radius: L(30), cdWhite)
        let border = c.minus(c.roundedRect(card, radius: L(30), cdWhite, alpha: 0.09),
                             c.roundedRect(card.insetBy(dx: L(1), dy: L(1)), radius: L(29), cdWhite))
        var g: [CIImage] = [c.roundedRect(card, radius: L(30), ink), border]

        // Shine bar: a skewed white band sweeping across 12%..26%.
        let st = Curve.easeInOut.track(p, [(0.12, -160), (0.26, 420)])
        let tx = L(90 * CGFloat(st) / 100)
        if tx > -L(120), tx < cardW {
            let k = CGFloat(tan(-20.0 * Double.pi / 180))
            let skew = CGAffineTransform(a: 1, b: 0, c: k, d: 1, tx: -k * card.midY, ty: 0)
            let bar = c.fill(CGRect(x: card.minX + tx, y: top, width: L(90), height: cardH), cdWhite, alpha: 0.12)
            g.append(c.clip(bar.transformed(by: skew), to: shape))
        }

        g.append(c.disc(CGPoint(x: left + L(26 + 46), y: mid.y), L(46), acc))
        g.append(c.text(info.initial, at: CGPoint(x: left + L(26 + 46), y: mid.y), size: L(40), weight: .heavy, color: ink, tracking: 0, face: "Unbounded"))
        g.append(c.text("\(String(info.name.uppercased().prefix(24))) DONATED", at: CGPoint(x: colX + labelW / 2, y: colTop + L(12.5)), size: L(18),
                        weight: .bold, color: acc, tracking: 0.2, face: "Manrope"))

        // Odometer: each digit column scrolls 10 + d digit heights (cubic ease-out), the next digit 0.07 s behind.
        let roll = Curve(0.15, 0.85, 0.25, 1)
        let lineTop = colTop + L(31), lineH = L(76)
        var x = colX, di = 0
        var cols: [CIImage] = []
        for (ch, w) in zip(chars, widths) {
            let cx = x + w / 2
            if ch >= "0" && ch <= "9", let d = Int(String(ch)) {
                let pp = p - Double(di) * 0.07 / dur
                let o = Double(10 + d) * roll.track(pp, [(0.08, 0), (0.36, 1)])
                let k0 = Int(o.rounded(.down))
                let f = CGFloat(o - Double(k0))
                for k in k0...(f > 0.001 ? k0 + 1 : k0) {
                    cols.append(c.text(String(k % 10), at: CGPoint(x: cx, y: lineTop + lineH / 2 + (CGFloat(k - k0) - f) * lineH), size: L(76),
                                       weight: .heavy, color: cdWhite, tracking: 0, face: "Unbounded"))
                }
                di += 1
            } else {
                cols.append(c.text(String(ch), at: CGPoint(x: cx, y: lineTop + lineH / 2), size: L(76), weight: .heavy, color: cdWhite, tracking: 0, face: "Unbounded"))
            }
            x += w
        }
        g.append(c.clip(c.stack(cols), to: c.fill(CGRect(x: colX, y: lineTop, width: amtW, height: lineH), cdWhite)))

        if hasMsg {
            let ma = cdEaseOut.track(p, [(0.20, 0), (0.28, 1), (0.84, 1), (0.92, 0)])
            let dy = cdEaseOut.track(p, [(0.20, 10), (0.28, 0)])
            g.append(c.text(info.message, at: CGPoint(x: colX + msgW / 2, y: colTop + L(25 + 6 + 76 + 6 + 15 + CGFloat(dy))), size: L(22), weight: .medium,
                            color: 0xFFC8_C9D0, alpha: CGFloat(ma), tracking: 0, scale: msgScale, face: "Manrope"))
        }

        // Pop in (overshoot), hold, drift up and fade; the pop pivots on the card's top centre.
        let pop = Curve(0.2, 0.9, 0.25, 1.15)
        let pa = min(1, max(0, pop.track(p, [(0, 0), (0.07, 1), (0.84, 1), (0.92, 0)])))
        let ps = pop.track(p, [(0, 0.6), (0.07, 1.06), (0.11, 1), (0.84, 1), (0.92, 0.96)])
        let pty = pop.track(p, [(0, -48), (0.07, 0), (0.84, 0), (0.92, -28)])
        var cardImg = c.transform(c.stack(g), about: CGPoint(x: mid.x, y: top), scale: CGFloat(ps))
        cardImg = cardImg.transformed(by: CGAffineTransform(translationX: 0, y: L(CGFloat(pty))))
        layers.append(c.opacity(cardImg, pa))
        return c.stack(layers)
    }

    // MARK: neon

    /// A neon sign: name and amount in glass tubes that flicker on, a frame, a coloured light spill, sparks, a message line.
    static func neon(p: Double, info: DonationAlertInfo, style: DonationAlertStyle, c: StingerCanvas, b: DonationBoard) -> CIImage {
        guard p < 0.9 else { return .empty() }
        let a: UInt32 = style.accent == 0 ? 0xFFFF_3DA6 : style.accent | 0xFF00_0000
        let sec: UInt32 = style.second == 0 ? 0xFF3D_E8FF : style.second | 0xFF00_0000
        let L = b.len
        let dur = 6 / max(style.speed, 0.1)
        let lin = Curve.linear

        // The boards' flicker keyframes: linear between stops, which reads as steps.
        let fa = lin.track(p, [(0, 0), (0.03, 0), (0.04, 1), (0.05, 0.1), (0.065, 1), (0.075, 0.25), (0.09, 1), (0.60, 1), (0.61, 0.35),
                               (0.62, 1), (0.84, 1), (0.85, 0.2), (0.86, 0.9), (0.88, 0), (1, 0)])
        let fb = lin.track(p, [(0, 0), (0.11, 0), (0.12, 1), (0.13, 0.15), (0.145, 1), (0.72, 1), (0.73, 0.4), (0.74, 1), (0.85, 1),
                               (0.86, 0.3), (0.87, 0.8), (0.89, 0), (1, 0)])
        let fs = lin.track(p, [(0, 0), (0.03, 0), (0.09, 1), (0.84, 1), (0.89, 0), (1, 0)])

        let name = String(info.name.prefix(14))
        let nameSize = L(118), amtSize = L(96)
        func tube(_ s: String, _ at: CGPoint, _ size: CGFloat, _ col: UInt32, alpha: CGFloat = 1) -> CIImage {
            c.text(s, at: at, size: size, weight: .regular, color: col, alpha: alpha, tracking: 0, face: "TiltNeon")
        }
        let nameW = cdW(tube(name, .zero, nameSize, cdWhite)), amtW = cdW(tube(info.amount, .zero, amtSize, cdWhite))
        let cx = b.pt(640, 0).x, top = b.pt(0, 96).y
        let signW = max(nameW, amtW) + L(128), signH = L(276.8)
        let sign = CGRect(x: cx - signW / 2, y: top, width: signW, height: signH)
        let nameC = CGPoint(x: cx, y: top + L(30 + 59))
        let amtC = CGPoint(x: cx, y: top + L(30 + 118 + 2 + 50.4))
        var layers: [CIImage] = []

        // Light spill: a big soft ellipse in the first colour (a radial falloff instead of a 140 px blur).
        if fs > 0.005 {
            let ctr = b.pt(640, 270)
            let glow = c.radial(ctr, L(150), L(390), a, a).cropped(to: CGRect(x: ctr.x - L(400), y: ctr.y - L(400), width: L(800), height: L(800)))
            let squash = CGAffineTransform(translationX: ctr.x, y: ctr.y).scaledBy(x: 1, y: 460 / 600).translatedBy(x: -ctr.x, y: -ctr.y)
            layers.append(c.opacity(glow.transformed(by: squash), fs * 0.4))
        }

        // Unlit glass: always there, barely visible.
        let hole = c.roundedRect(sign.insetBy(dx: L(4), dy: L(4)), radius: L(36), cdWhite)
        layers.append(c.minus(c.roundedRect(sign, radius: L(40), cdWhite, alpha: 0.07), hole))
        layers.append(tube(name, nameC, nameSize, cdWhite, alpha: 0.07))
        layers.append(tube(info.amount, amtC, amtSize, cdWhite, alpha: 0.07))

        // Lit tubes: the bright core plus three blurred copies in the tube colour, screened together.
        func lit(_ src: CIImage, _ core: CIImage, _ col: UInt32, _ alpha: Double) -> CIImage {
            let halo = c.screen(cdSoft(c, src, L(45)), over: c.screen(cdSoft(c, src, L(22)), over: cdSoft(c, src, L(9))))
            return c.opacity(core.composited(over: halo), alpha)
        }
        if fa > 0.005 {
            let frame = c.minus(c.roundedRect(sign, radius: L(40), a), hole)
            let src = c.stack([frame, tube(name, nameC, nameSize, a)])
            let core = c.stack([c.minus(c.roundedRect(sign, radius: L(40), 0xFFFF_E3F2), hole), tube(name, nameC, nameSize, 0xFFFF_E6F3)])
            layers.append(lit(src, core, a, fa))
        }
        if fb > 0.005 {
            layers.append(lit(tube(info.amount, amtC, amtSize, sec), tube(info.amount, amtC, amtSize, 0xFFE3_FBFF), sec, fb))
        }

        // Sparks drop from the sign's bottom edge, accelerating, 4%..22%.
        let drop = Curve(0.3, 0, 0.8, 0.6)
        let xs: [CGFloat] = [-120, -70, -40, -12, 14, 38, 66, 98, 130]
        for (i, x0) in xs.enumerated() {
            let pp = p - Double(i % 3) * 0.05 / dur
            guard pp >= 0.04, pp < 0.22 else { continue }
            let f = drop.track(pp, [(0.04, 0), (0.22, 1)])
            let pos = CGPoint(x: cx + L(x0 * 1.6 + 2.5 + x0 * 0.5 * CGFloat(f)), y: sign.maxY + L(2.5 + 220 * CGFloat(f)))
            let al = CGFloat(1 - f)
            layers.append(c.radial(pos, 0, L(9), 0xFFFF_D36B, 0xFFFF_D36B, alphaA: 0.55 * al, alphaB: 0)
                .cropped(to: CGRect(x: pos.x - L(10), y: pos.y - L(10), width: L(20), height: L(20))))
            layers.append(c.disc(pos, L(2.5), 0xFFFF_F6C8, alpha: al))
        }

        // Message (Persian reads right to left; centred, so only the shaping matters).
        if !info.message.isEmpty {
            let ma = cdEaseOut.track(p, [(0.16, 0), (0.20, 1), (0.84, 1), (0.88, 0)])
            let w = cdW(c.text(info.message, at: .zero, size: L(30), weight: .regular, color: cdWhite, tracking: 0, face: "Vazirmatn"))
            layers.append(c.text(info.message, at: CGPoint(x: cx, y: sign.maxY + L(28 + 24)), size: L(30), weight: .regular, color: 0xFFF1_EEF6,
                                 alpha: CGFloat(ma), tracking: 0, scale: min(1, L(1100) / max(w, 1)), face: "Vazirmatn"))
        }
        return c.stack(layers)
    }

    // MARK: receipt

    /// A tip printer feeds a paper receipt out in 16 steps; a THANK YOU stamp slams on it; then it tears off and falls.
    static func receipt(p: Double, info: DonationAlertInfo, style: DonationAlertStyle, c: StingerCanvas, b: DonationBoard) -> CIImage {
        guard p < 0.97 else { return .empty() }
        let acc: UInt32 = style.accent == 0 ? 0xFFE5_352B : style.accent | 0xFF00_0000
        let paperC: UInt32 = 0xFFF3_F0E6, ink: UInt32 = 0xFF18_181B
        let L = b.len, s = b.s
        let o = b.pt(850, 80)
        let face = "JetBrainsMono"
        func Q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }

        /// A text line anchored at its left (or right) edge, `y` the line's middle, all in paper-local board px.
        func line(_ str: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: UIFont.Weight = .medium, _ tr: CGFloat = 0, right: Bool = false) -> CIImage {
            let w = cdW(c.text(str, at: .zero, size: L(size), weight: weight, color: ink, tracking: tr, face: face))
            let at = Q(x, y)
            return c.text(str, at: CGPoint(x: right ? at.x - w / 2 : at.x + w / 2, y: at.y), size: L(size), weight: weight, color: ink, tracking: tr, face: face)
        }

        // Paper content, laid out top to bottom like the board's flex column (28 px top padding, 10 px gaps).
        var rows: [CIImage] = []
        var y: CGFloat = 28
        func next(_ h: CGFloat) -> CGFloat { let m = y + h / 2; y += h + 10; return m }
        func rule() {
            let f = CIFilter.stripesGenerator()
            f.center = Q(24, y + 4)
            f.color0 = StingerCanvas.ciColor(ink)
            f.color1 = StingerCanvas.ciColor(ink, alpha: 0)
            f.width = Float(L(5))
            f.sharpness = 1
            rows.append((f.outputImage ?? .empty()).cropped(to: CGRect(origin: Q(24, y + 4), size: CGSize(width: L(272), height: L(2)))))
            y += 2 + 8 + 10
        }
        func pair(_ l: String, _ r: String, bold: Bool = false) {
            let m = next(21)
            rows.append(line(l, 24, m, 16))
            rows.append(line(r, 296, m, 16, bold ? .heavy : .medium, right: true))
        }

        rows.append(c.text("METASTREAM", at: Q(160, next(29)), size: L(22), weight: .heavy, color: ink, tracking: 0.12, face: face))
        rows.append(c.text("DONATION RECEIPT", at: Q(160, next(17)), size: L(13), weight: .medium, color: ink, tracking: 0.3, face: face))
        rule()
        pair(info.date, info.time)
        pair("FROM", String(info.name.uppercased().prefix(16)))
        pair("VIA", String(info.source.uppercased().prefix(16)))
        let am = next(32)
        rows.append(line("AMOUNT", 24, am + 4, 16))
        rows.append(line(info.amount, 296, am, 24, .heavy, right: true))
        if !info.rate.isEmpty { pair("RATE", info.rate) }
        if !info.toGoal.isEmpty { pair("TO GOAL", info.toGoal, bold: true) }
        rule()
        if !info.message.isEmpty {
            let lines = cdWrap("\"\(info.message.replacingOccurrences(of: "\n", with: " "))\"", 28, 3)
            let rtl = info.message.unicodeScalars.contains { $0.value >= 0x0600 && $0.value <= 0x06FF }
            let t = y
            _ = next(CGFloat(lines.count) * 23.2)
            for (i, ln) in lines.enumerated() {
                let m = t + (CGFloat(i) + 0.5) * 23.2
                rows.append(rtl ? line(ln, 296, m, 16, right: true) : line(ln, 24, m, 16))
            }
        }
        let barTop = y + 6
        y += 6 + 54 + 10
        let bars = cdBitmap("bars|\(Int(s * 1000))", CGSize(width: 272 * s, height: 54 * s)) { ctx in
            ctx.scaleBy(x: s, y: s)
            ctx.setFillColor(StingerArt.color(ink))
            for base in stride(from: CGFloat(0), to: 272, by: 16) {
                for (dx, w) in [(CGFloat(0), CGFloat(3)), (5, 1), (10, 4)] where base + dx < 272 {
                    ctx.fill(CGRect(x: base + dx, y: 0, width: min(w, 272 - base - dx), height: 54))
                }
            }
        }
        rows.append(bars.transformed(by: CGAffineTransform(translationX: Q(24, barTop).x, y: Q(24, barTop).y)))
        var h: UInt32 = 2_166_136_261   // FNV-1a: a short stable receipt id from the donation
        for u in (info.name + info.amount + info.time).utf8 { h = (h ^ UInt32(u)) &* 16_777_619 }
        rows.append(c.text("#MS-" + String(format: "%05d", Int(h % 100_000)), at: Q(160, next(16)), size: L(12), weight: .medium, color: ink,
                           tracking: 0.2, face: face))
        let hp = y + 24   // paper height: bottom padding 34 less the last gap

        // Paper body with a zigzag tear edge (16 px teeth, 10 px deep).
        let zig = cdBitmap("zig|\(Int(s * 1000))", CGSize(width: 320 * s, height: 10 * s)) { ctx in
            ctx.scaleBy(x: s, y: s)
            ctx.setFillColor(StingerArt.color(paperC))
            ctx.move(to: .zero)
            ctx.addLine(to: CGPoint(x: 320, y: 0))
            for x in stride(from: 320, through: 0, by: -16) { ctx.addLine(to: CGPoint(x: CGFloat(x), y: (x / 16) % 2 == 0 ? 10 : 0)) }
            ctx.closePath()
            ctx.fillPath()
        }
        let body = c.fill(CGRect(origin: o, size: CGSize(width: L(320), height: L(hp - 10))), paperC)
        var paper = c.stack([body, zig.transformed(by: CGAffineTransform(translationX: o.x, y: Q(0, hp - 10).y))] + rows)

        // Stamp: slams down at 40%..47%, multiplied onto the paper.
        let stampC = Curve(0.2, 0.8, 0.3, 1.2)
        let sa = min(1, max(0, stampC.track(p, [(0.40, 0), (0.44, 1)])))
        if sa > 0.005 {
            let tw = cdW(c.text("THANK YOU", at: .zero, size: L(34), weight: .heavy, color: acc, tracking: 0.08, face: face))
            let sw = tw + L(36 + 10), sh = L(45 + 16 + 10)
            let ctr = CGPoint(x: Q(58, 0).x + sw / 2, y: Q(0, 250).y + sh / 2)
            let r = CGRect(x: ctr.x - sw / 2, y: ctr.y - sh / 2, width: sw, height: sh)
            let frame = c.minus(c.roundedRect(r, radius: L(10), acc), c.roundedRect(r.insetBy(dx: L(5), dy: L(5)), radius: L(5), cdWhite))
            let word = c.text("THANK YOU", at: ctr, size: L(34), weight: .heavy, color: acc, tracking: 0.08, face: face)
            let ss = CGFloat(stampC.track(p, [(0.40, 2.6), (0.44, 0.94), (0.47, 1)]))
            let stamp = c.opacity(c.transform(c.stack([frame, word]), about: ctr, scale: ss, rotate: -14), sa)
            paper = stamp.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: paper])
        }

        // Paper motion: 16 hard steps out of the printer, hold, a small drop at 78%, then fall and spin away.
        let hpC = L(hp)
        var dy: CGFloat = -hpC, rot: CGFloat = 0
        if p >= 0.38 && p < 0.78 {
            dy = 0
        } else if p >= 0.07 && p < 0.38 {
            dy = -hpC * (1 - CGFloat((Key.span(p, 0.07, 0.38) * 16).rounded(.down) / 16))
        } else if p >= 0.78 && p < 0.80 {
            let e = CGFloat(Curve(0.5, 0, 0.9, 0.4)((p - 0.78) / 0.02))
            dy = L(6) * e
            rot = -e
        } else if p >= 0.80 {
            let ease = Curve.ease
            let e = CGFloat(ease((p - 0.80) / 0.16))
            dy = L(6 + 754 * e)
            rot = -1 + 15 * e
        }
        paper = c.transform(paper, about: Q(160, 0), rotate: rot).transformed(by: CGAffineTransform(translationX: 0, y: dy))
        let sheet = c.clip(paper, to: c.fill(b.rect(850, 80, 320, 640), cdWhite))

        // Printer bar with its LED: grey, the accent while printing, then green.
        let pa = cdEaseOut.track(p, [(0, 0), (0.05, 1), (0.90, 1), (0.97, 0)])
        let pty = cdEaseOut.track(p, [(0, -30), (0.05, 0), (0.90, 0), (0.97, -30)])
        let led: UInt32 = p < 0.08 ? 0xFF3A_3B40 : p < 0.38 ? acc : 0xFF53_FC18
        let tipW = cdW(c.text("TIP PRINTER", at: .zero, size: L(13), weight: .heavy, color: 0xFF8B_8D96, tracking: 0.24, face: face))
        let tip = c.text("TIP PRINTER", at: CGPoint(x: b.pt(838, 0).x + tipW / 2, y: b.pt(0, 63).y), size: L(13), weight: .heavy, color: 0xFF8B_8D96,
                         tracking: 0.24, face: face)
        var printer = c.stack([c.roundedRect(b.rect(820, 48, 380, 50), radius: L(14), 0xFF1A_1B1F),
                               c.roundedRect(b.rect(820, 38, 380, 50), radius: L(14), 0xFF24_252B), tip, c.disc(b.pt(1176, 63), L(6), led)])
        printer = c.opacity(printer.transformed(by: CGAffineTransform(translationX: 0, y: L(CGFloat(pty)))), pa)
        return c.stack([sheet, printer])
    }
}
