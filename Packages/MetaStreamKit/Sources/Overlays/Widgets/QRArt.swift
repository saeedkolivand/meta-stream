// The QR widget drawn on the GPU: CIQRCodeGenerator (a Core Image filter) scaled with nearest-neighbour so module edges stay
// crisp for scanners, on the background colour, with the caption under it. QRCode.image (WidgetViews.swift) stays the
// editor preview's CPU renderer.
// ponytail: the caption is one line, cut with an ellipsis (the bitmap path could wrap to a second line).
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum QRArt {
    /// A still scene for `box` (top-left coordinates inside the widget); nil when there is nothing to encode.
    static func scene(_ style: QRWidgetStyle, box: CGRect) -> GPUScene? {
        let size = CGSize(width: box.width.rounded(), height: box.height.rounded())
        guard !style.text.isEmpty, size.width >= 8, size.height >= 8 else { return nil }
        let area = CGRect(origin: box.origin, size: size)
        return GPUScene(draw: { pen, _ in
            pen.stack([pen.fill(area, style.background), code(style, pen, area), caption(style, pen, area)])
        })
    }

    /// The code in a square of `area.width` with 6 % padding, scaled by whole pixels per module when it fits.
    private static func code(_ style: QRWidgetStyle, _ pen: StingerCanvas, _ area: CGRect) -> CIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(style.text.utf8)
        filter.correctionLevel = "M"
        guard let raw = filter.outputImage else { return .empty() }
        let side = area.width, pad = side * 0.06, avail = side - 2 * pad, modules = raw.extent.width
        let whole = max(1, floor(avail / modules))
        let scale = whole * modules <= avail ? whole : avail / modules
        let colored = raw.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": StingerCanvas.ciColor(style.foreground), "inputColor1": StingerCanvas.ciColor(style.background)
        ])
        let drawn = modules * scale
        // Upright in top-left space first (the scene is flipped once at the end), then scaled with no smoothing.
        return colored.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: modules))
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: area.minX + (side - drawn) / 2, y: area.minY + (side - drawn) / 2))
    }

    /// The caption centred in the strip under the code.
    private static func caption(_ style: QRWidgetStyle, _ pen: StingerCanvas, _ area: CGRect) -> CIImage {
        let side = area.width, strip = area.height - side
        guard !style.caption.isEmpty, strip > 0 else { return .empty() }
        let points = min(strip * 0.45, side * 0.085)
        let room = side * 0.88
        let font = WidgetFonts.uiFont(face: style.face, size: points, weight: .semibold)
        func wide(_ text: String) -> CGFloat { ceil((text as NSString).size(withAttributes: [.font: font]).width) }
        var line = style.caption
        while line.count > 1, wide(line) > room { line = String(line.dropLast()) }
        if line != style.caption { line = String(line.dropLast()) + "…" }
        return pen.text(line, at: CGPoint(x: area.midX, y: area.minY + side + strip / 2), size: points, weight: .semibold,
                        color: style.foreground, tracking: 0, face: style.face)
    }
}
