// The "Island" alert drawn on the GPU, like the donation alerts: AlertBannerView's look as a recipe on a StingerCanvas.
// Every frame is a pure function of t (AlertIsland.pose), in the top-left canvas coordinates of the Alerts widget's box,
// where the banner's 900x240 natural area sits scaled by box.width / 900 (what WidgetRaster.piece does for the CPU path).
import AVFoundation
import CoreGraphics
import CoreImage
import HaishinKit
import SwiftUI
import UIKit

enum IslandArt {
    private static let steps = 24.0   // the count-up changes the text this often, so the text cache isn't thrashed

    private static func metrics(_ s: String, _ size: CGFloat, _ weight: UIFont.Weight, _ tracking: CGFloat, _ face: String)
        -> (w: CGFloat, h: CGFloat, asc: CGFloat) {
        let f = WidgetFonts.uiFont(face: face, size: size, weight: weight)
        let b = NSAttributedString(string: s, attributes: [.font: f, .kern: tracking * size]).size()
        return (ceil(b.width), ceil(b.height), f.ascender)
    }

    /// `s` with its left edge at `left` and its baseline at `baseline`.
    private static func put(_ c: StingerCanvas, _ s: String, left: CGFloat, baseline: CGFloat, size: CGFloat, weight: UIFont.Weight,
                            color: UInt32, alpha: CGFloat = 1, tracking: CGFloat = 0, face: String) -> CIImage {
        let m = metrics(s, size, weight, tracking, face)
        return c.text(s, at: CGPoint(x: left + m.w / 2 - tracking * size / 2, y: baseline - m.asc + m.h / 2), size: size, weight: weight,
                      color: color, alpha: alpha, tracking: tracking, face: face)
    }

    static func frame(event e: ChatEvent, style: AlertWidgetStyle, t: Double, hold: Int, big: Bool, c: StingerCanvas, box: CGRect) -> CIImage {
        let pose = AlertIsland.pose(at: t, hold: hold, big: big)
        let u = box.width / 900, vis = box.intersection(c.bounds)
        guard u > 0, pose.alpha > 0.001, !vis.isNull, vis.width > 0, vis.height > 0 else { return .empty() }
        let h = AlertIsland.height(big: big), full = AlertIsland.fullWidth(big: big)
        let tint = AlertIsland.color(e.kind, accent: style.accentColor)
        let w = h + (full - h) * max(0, pose.open)
        let top = 56 + pose.lift * h   // natural y of the capsule (56 = room above the rest position for the dot to drop in)
        let cap = CGRect(x: box.minX + (450 - w / 2) * u, y: box.minY + top * u, width: w * u, height: h * u)
        let shape = c.roundedRect(cap, radius: h * u / 2, 0xFF0D_0D10)
        var layers = [shape]
        if pose.contentAlpha > 0.001 {
            let left = box.minX + (450 - full / 2) * u   // the content frame stays put while the capsule opens over it
            let midY = box.minY + (top + h / 2 + pose.contentRise) * u
            let q = (pose.progress * steps).rounded() / steps
            let art = c.stack(content(e, style: style, q: q, big: big, tint: tint, c: c, u: u, left: left, midY: midY))
            layers.append(c.clip(c.opacity(art, Double(pose.contentAlpha)), to: shape))
        }
        layers.append(c.roundedRect(cap, radius: h * u / 2, tint, alpha: CGFloat(pose.flash)))   // big-tier flash
        return c.opacity(c.stack(layers), Double(pose.alpha)).cropped(to: vis)
    }

    /// Icon disc + symbol, label/name/message column and the amount, laid out like AlertBannerView.content.
    private static func content(_ e: ChatEvent, style: AlertWidgetStyle, q: Double, big: Bool, tint: UInt32, c: StingerCanvas, u: CGFloat,
                                left: CGFloat, midY: CGFloat) -> [CIImage] {
        let face = style.face, fs = CGFloat(style.fontSize) * u
        let h = AlertIsland.height(big: big), full = AlertIsland.fullWidth(big: big), d = AlertIsland.iconSize(big: big)
        let pad = (h - d) / 2, gap = AlertIsland.gapX * u
        var out: [CIImage] = []

        let iconC = CGPoint(x: left + (pad + d / 2) * u, y: midY)
        out.append(c.disc(iconC, d * u / 2, tint))
        out.append(c.symbol(eventSymbol(e.kind).name, pointSize: d * u * 0.46, color: e.kind == .follow ? 0xFF11_1111 : 0xFFFF_FFFF, at: iconC))

        // Amount: right-aligned, shrunk once (from its final text, so it doesn't jitter while counting) to fit its cap.
        let right = left + (full - AlertIsland.padTrailing) * u
        var amountW: CGFloat = 0
        if let end = AlertIsland.amountParts(e, progress: 1), let now = AlertIsland.amountParts(e, progress: q) {
            let size = fs * (big ? 1.8 : 1.3)
            func width(_ a: (number: String, unit: String), _ k: CGFloat) -> CGFloat {
                metrics(a.number, size * k, .bold, 0, face).w + (a.unit.isEmpty ? 0 : metrics(" " + a.unit, size * k / 2, .bold, 0, face).w)
            }
            let k = min(1, max(0.5, AlertIsland.amountMax(big: big) * u / max(width(end, 1), 1)))
            amountW = width(end, k)
            let n = metrics(now.number, size * k, .bold, 0, face), unit = " " + now.unit
            let x0 = right - n.w - (now.unit.isEmpty ? 0 : metrics(unit, size * k / 2, .bold, 0, face).w)
            let baseline = midY - n.h / 2 + n.asc
            out.append(put(c, now.number, left: x0, baseline: baseline, size: size * k, weight: .bold, color: tint, face: face))
            if !now.unit.isEmpty {
                out.append(put(c, unit, left: x0 + n.w, baseline: baseline, size: size * k / 2, weight: .bold, color: tint, face: face))
            }
        }

        // Name column: the name takes what the amount leaves and shrinks to half before it is cut.
        let colX = left + (pad + d) * u + gap
        let colW = AlertIsland.share(big: big) * u + (amountW > 0 ? -amountW : gap)
        let label = AlertIsland.label(e), msg0 = e.text.replacingOccurrences(of: "\n", with: " ")
        let lm = metrics(label, fs * 0.45, .semibold, 0.16, face)
        let nm0 = metrics(e.user, fs, .bold, 0, face)
        let nSize = nm0.w > colW ? fs * max(0.5, colW / nm0.w) : fs
        let nm = metrics(e.user, nSize, .bold, 0, face)
        var msg = msg0
        let mm0 = metrics(msg0, fs * 0.55, .regular, 0, face)
        if mm0.w > colW, !msg0.isEmpty { msg = String(msg0.prefix(max(1, Int(CGFloat(msg0.count) * colW / mm0.w) - 1))) + "…" }
        let mm = metrics(msg, fs * 0.55, .regular, 0, face)
        let sp = 2 * u
        var y = midY - (lm.h + sp + nm.h + (msg.isEmpty ? 0 : sp + mm.h)) / 2
        func line(_ s: String, _ m: (w: CGFloat, h: CGFloat, asc: CGFloat), size: CGFloat, weight: UIFont.Weight, color: UInt32,
                  alpha: CGFloat = 1, tracking: CGFloat = 0) {
            let img = put(c, s, left: colX, baseline: y + m.asc, size: size, weight: weight, color: color, alpha: alpha, tracking: tracking, face: face)
            out.append(c.clip(img, to: c.fill(CGRect(x: colX, y: y, width: colW, height: m.h), 0xFFFF_FFFF)))   // cut at the column
            y += m.h + sp
        }
        line(label, lm, size: fs * 0.45, weight: .semibold, color: 0xFFFF_FFFF, alpha: 0.74, tracking: 0.16)
        line(e.user, nm, size: nSize, weight: .bold, color: style.textColor)
        if !msg.isEmpty { line(msg, mm, size: fs * 0.55, weight: .regular, color: 0xFFFF_FFFF, alpha: 0.74) }
        return out
    }
}

extension StingerCanvas {
    /// An SF Symbol (bold) in `argb`, centred on `p`; rendered once per name/size/colour and cached on the canvas.
    func symbol(_ name: String, pointSize: CGFloat, color argb: UInt32, at p: CGPoint) -> CIImage {
        let key = "\(name)|\(Int(pointSize.rounded()))|\(argb)"
        let image: CGImage
        if let hit = symbols[key] {
            image = hit
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
            guard let sym = UIImage(systemName: name, withConfiguration: cfg)?
                .withTintColor(UIColor(cgColor: StingerArt.color(argb)), renderingMode: .alwaysOriginal) else { return .empty() }
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            fmt.opaque = false
            let box = CGSize(width: ceil(sym.size.width), height: ceil(sym.size.height))
            guard box.width > 0, box.height > 0, let cg = UIGraphicsImageRenderer(size: box, format: fmt).image(actions: { _ in
                sym.draw(at: CGPoint(x: (box.width - sym.size.width) / 2, y: (box.height - sym.size.height) / 2))
            }).cgImage else { return .empty() }
            symbols[key] = cg
            image = cg
        }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        return CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h))   // into top-left space, like text
            .transformed(by: CGAffineTransform(translationX: p.x - w / 2, y: p.y - h / 2))
    }
}

/// An Island alert as a screen object: same structure as DonationAlertScreenObject, with t in seconds since it started.
final class AlertIslandScreenObject: ScreenObject {
    private let event: ChatEvent
    private let style: AlertWidgetStyle
    private let hold: Int
    private let big: Bool
    private let box: CGRect   // the Alerts widget's box on the canvas
    private var start: CMTime?
    private var canvas: StingerCanvas?
    // perf: frames drawn, draw time, and the longest gap between video frames, logged once when it ends
    private var frames = 0
    private var drawTotal = 0.0, drawMax = 0.0, gapMax = 0.0
    private var last = 0.0
    private var logged = false

    init(event: ChatEvent, style: AlertWidgetStyle, hold: Int, big: Bool, box: CGRect) {
        self.event = event
        self.style = style
        self.hold = hold
        self.big = big
        self.box = box
        super.init()
    }

    override func makeImage(_ renderer: some ScreenRenderer) -> CIImage? {
        let now = renderer.presentationTimeStamp
        let first = start ?? now
        start = first
        let t = (now - first).seconds
        // An empty image (not nil) once it's over: nil would leave the renderer's last frame on screen.
        guard t.isFinite, t >= 0, t <= AlertIsland.total(hold: hold) else {
            if !logged, frames > 0 {
                logged = true
                applog("perf", "island alert \(event.kind): \(frames) frames in \(String(format: "%.2f", last)) s "
                       + "(\(String(format: "%.0f", Double(frames) / max(last, 0.01))) fps), draw avg \(String(format: "%.1f", drawTotal / Double(frames))) ms "
                       + "max \(String(format: "%.1f", drawMax)) ms, longest gap \(String(format: "%.0f", gapMax * 1000)) ms, "
                       + "canvas \(Int(bounds.width))x\(Int(bounds.height)), renderer \(type(of: renderer))")
            }
            return CIImage.empty()
        }
        let began = CACurrentMediaTime()
        let k = canvas?.size == bounds.size ? canvas! : StingerCanvas(size: bounds.size)
        canvas = k
        // Top-left art flipped once into Core Image's bottom-left space and cut to the canvas, like DonationAlertScreenObject.
        let image = IslandArt.frame(event: event, style: style, t: t, hold: hold, big: big, c: k, box: box)
            .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: k.size.height))
            .cropped(to: k.bounds)
        let ms = (CACurrentMediaTime() - began) * 1000
        frames += 1
        drawTotal += ms
        drawMax = max(drawMax, ms)
        if frames > 1 { gapMax = max(gapMax, t - last) }
        last = t
        return image
    }
}
