// Draws overlay layers (image, text, color, browser snapshot) into bitmaps at their final output size.
// HaishinKit's CPU renderer blits an ImageScreenObject's CGImage 1:1 at its origin (no scaling, and overflow past the
// canvas is only guarded by cropping), so every bitmap is pre-scaled and pre-clipped to the stream canvas here.
import AVFoundation
import UIKit

/// CGImage isn't Sendable in every SDK; a finished bitmap is never mutated, so handing it across actors is safe.
struct OverlayBitmap: @unchecked Sendable { let image: CGImage }

/// A bitmap and where it lands in the stream canvas (whole px, always inside the canvas).
struct OverlayPiece: Sendable {
    let bitmap: OverlayBitmap
    let rect: CGRect
}

@MainActor
enum OverlayRaster {
    /// `box` (output px, may hang off the canvas) clipped to the canvas, in whole px; nil when nothing is left.
    static func visible(_ box: CGRect, in canvas: CGSize) -> CGRect? {
        let r = box.integral.intersection(CGRect(origin: .zero, size: canvas))
        return r.isNull || r.width < 1 || r.height < 1 ? nil : r
    }

    /// Runs `draw` with the full box in a bitmap covering only the visible part.
    static func render(_ box: CGRect, canvas: CGSize, draw: (CGRect) -> Void) -> OverlayPiece? {
        guard let vis = visible(box, in: canvas) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard   // 8-bit sRGB: what HaishinKit's vImage path expects
        let img = UIGraphicsImageRenderer(size: vis.size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: -vis.minX, y: -vis.minY)
            draw(box)
        }
        return img.cgImage.map { OverlayPiece(bitmap: OverlayBitmap(image: $0), rect: vis) }
    }

    // MARK: layer kinds

    /// File decoded at scale 1 (so `size` is pixels, whatever "@2x" the name carries).
    static func load(_ url: URL) -> UIImage? {
        (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }
    }

    /// Natural size after OBS crop (left, top, right, bottom).
    static func croppedSize(_ img: UIImage, _ crop: [Int]) -> CGSize {
        CGSize(width: img.size.width - CGFloat(crop[0] + crop[2]), height: img.size.height - CGFloat(crop[1] + crop[3]))
    }

    /// `img` cropped and stretched into `box`. The full image is drawn oversized and clipped, so no crop copy is made.
    static func drawImage(_ img: UIImage, crop: [Int], in box: CGRect) {
        let c = croppedSize(img, crop)
        guard c.width > 0, c.height > 0, let ctx = UIGraphicsGetCurrentContext() else { return }
        let sx = box.width / c.width, sy = box.height / c.height
        ctx.saveGState()
        ctx.clip(to: box)
        img.draw(in: CGRect(x: box.minX - CGFloat(crop[0]) * sx, y: box.minY - CGFloat(crop[1]) * sy,
                            width: img.size.width * sx, height: img.size.height * sy))
        ctx.restoreGState()
    }

    nonisolated static func color(argb: UInt32) -> UIColor {   // pure: also used by SwiftUI widget views
        UIColor(red: CGFloat((argb >> 16) & 255) / 255, green: CGFloat((argb >> 8) & 255) / 255,
                blue: CGFloat(argb & 255) / 255, alpha: CGFloat(argb >> 24) / 255)
    }

    static func fill(argb: UInt32, in box: CGRect) {
        color(argb: argb).setFill()
        UIRectFill(box)
    }

    /// OBS text sizes are canvas px, so callers pass `size * canvas-to-output scale`. Natural alignment/direction
    /// lets Persian/Arabic lines lay out right-to-left; the font carries a Vazirmatn cascade (see WidgetFonts).
    static func textAttributes(face: String, bold: Bool, px: CGFloat, argb: UInt32) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.baseWritingDirection = .natural
        para.alignment = .natural
        return [.font: WidgetFonts.uiFont(face: face, size: px, weight: bold ? .bold : .regular),
                .foregroundColor: color(argb: argb), .paragraphStyle: para]
    }

    static func textSize(_ text: String, _ attrs: [NSAttributedString.Key: Any]) -> CGSize {
        let big = CGFloat.greatestFiniteMagnitude
        let s = (text as NSString).boundingRect(with: CGSize(width: big, height: big), options: .usesLineFragmentOrigin, attributes: attrs, context: nil).size
        return CGSize(width: ceil(s.width) + 2, height: ceil(s.height))
    }

    /// Draws `text` measured at `natural`, stretched into `box` (the layer's own scale).
    static func drawText(_ text: String, _ attrs: [NSAttributedString.Key: Any], natural: CGSize, in box: CGRect) {
        guard natural.width > 0, natural.height > 0, let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.translateBy(x: box.minX, y: box.minY)
        ctx.scaleBy(x: box.width / natural.width, y: box.height / natural.height)
        (text as NSString).draw(with: CGRect(origin: .zero, size: natural), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        ctx.restoreGState()
    }

    // MARK: in-app text (layout != nil): sized for a 1080 short side, optional shadow and rounded background

    /// Breathing room around the glyphs: a backdrop needs a margin, a shadow needs room to fall into the bitmap.
    private static func textPad(_ s: TextWidgetStyle) -> CGFloat { s.background ? s.size * 0.3 : s.shadow ? s.size * 0.1 : 0 }

    private static func textAttributes(_ s: TextWidgetStyle) -> [NSAttributedString.Key: Any] {
        var a = textAttributes(face: s.face, bold: s.bold, px: s.size, argb: s.color)
        if s.shadow {
            let sh = NSShadow()
            sh.shadowColor = UIColor.black.withAlphaComponent(0.6)
            sh.shadowOffset = CGSize(width: 0, height: s.size * 0.04)
            sh.shadowBlurRadius = s.size * 0.08
            a[.shadow] = sh
        }
        return a
    }

    /// Natural size of an in-app text widget, padding included (the compositor and the store both size from this).
    static func textNatural(_ s: TextWidgetStyle) -> CGSize {
        let t = textSize(s.text, textAttributes(s))
        let pad = textPad(s)
        return CGSize(width: t.width + 2 * pad, height: t.height + 2 * pad)
    }

    /// In-app text stretched from its natural size into `box`: backdrop first, then the glyphs inset by the padding.
    static func drawWidgetText(_ s: TextWidgetStyle, natural: CGSize, in box: CGRect) {
        guard natural.width > 0, natural.height > 0, let ctx = UIGraphicsGetCurrentContext() else { return }
        let pad = textPad(s)
        ctx.saveGState()
        ctx.translateBy(x: box.minX, y: box.minY)
        ctx.scaleBy(x: box.width / natural.width, y: box.height / natural.height)
        if s.background {
            color(argb: s.backgroundColor).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: natural), cornerRadius: s.size * 0.25).fill()
        }
        let inner = CGRect(x: pad, y: pad, width: natural.width - 2 * pad, height: natural.height - 2 * pad)
        (s.text as NSString).draw(with: inner, options: .usesLineFragmentOrigin, attributes: textAttributes(s), context: nil)
        ctx.restoreGState()
    }

    /// `b` redrawn at opacity `a` (ScreenObject has no alpha, so fades re-draw the stored full-opacity bitmap). nil = invisible.
    static func withAlpha(_ b: OverlayBitmap, _ a: CGFloat) -> OverlayBitmap? {
        guard a > 0 else { return nil }
        guard a < 1 else { return b }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let size = CGSize(width: b.image.width, height: b.image.height)
        let img = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: b.image).draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: a)
        }
        return img.cgImage.map { OverlayBitmap(image: $0) }
    }

    /// Pixel size of a clip's first video track, rotation applied. Synchronous on purpose (no AVAssetTrack across awaits).
    nonisolated static func mediaSize(_ url: URL) -> CGSize? {
        guard let t = AVURLAsset(url: url).tracks(withMediaType: .video).first else { return nil }
        let s = t.naturalSize.applying(t.preferredTransform)
        return CGSize(width: abs(s.width), height: abs(s.height))
    }
}
