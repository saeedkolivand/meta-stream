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

    static func color(argb: UInt32) -> UIColor {
        UIColor(red: CGFloat((argb >> 16) & 255) / 255, green: CGFloat((argb >> 8) & 255) / 255,
                blue: CGFloat(argb & 255) / 255, alpha: CGFloat(argb >> 24) / 255)
    }

    static func fill(argb: UInt32, in box: CGRect) {
        color(argb: argb).setFill()
        UIRectFill(box)
    }

    /// OBS text sizes are canvas px, so callers pass `size * canvas-to-output scale`.
    static func textAttributes(face: String, bold: Bool, px: CGFloat, argb: UInt32) -> [NSAttributedString.Key: Any] {
        let named = UIFont(name: face, size: px) ?? UIFont.fontNames(forFamilyName: face).first.flatMap { UIFont(name: $0, size: px) }
        var font = named ?? UIFont.systemFont(ofSize: px)
        if bold, let d = font.fontDescriptor.withSymbolicTraits(.traitBold) { font = UIFont(descriptor: d, size: px) }
        return [.font: font, .foregroundColor: color(argb: argb)]
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

    /// Pixel size of a clip's first video track, rotation applied. Synchronous on purpose (no AVAssetTrack across awaits).
    nonisolated static func mediaSize(_ url: URL) -> CGSize? {
        guard let t = AVURLAsset(url: url).tracks(withMediaType: .video).first else { return nil }
        let s = t.naturalSize.applying(t.preferredTransform)
        return CGSize(width: abs(s.width), height: abs(s.height))
    }
}
