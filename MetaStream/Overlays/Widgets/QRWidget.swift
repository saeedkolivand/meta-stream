// Native QR code: static, so it is rendered once and has no task.
import UIKit

extension OverlayCompositor {
    func qrWidget(_ l: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        let style = QRWidgetStyle(l.data)
        guard let rect = OverlayRaster.visible(box, in: canvas),
              let img = QRCode.image(style.text, style: style, size: CGSize(width: box.width.rounded(), height: box.height.rounded())),
              let piece = OverlayRaster.render(box, canvas: canvas, draw: { img.draw(in: $0) }) else { return nil }
        let o = await OverlayScreen.makeImage(rect, piece.bitmap)
        let object: ScreenObject = o
        return WidgetBuild(object: object, task: nil)
    }
}
