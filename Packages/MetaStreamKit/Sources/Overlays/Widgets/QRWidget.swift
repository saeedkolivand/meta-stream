// Native QR code on the GPU (QRArt.swift): a still scene drawn once, so it has no task.
import HaishinKit
import UIKit

extension OverlayCompositor {
    func qrWidget(_ l: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        let style = QRWidgetStyle(l.data)
        guard let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        // The box inside the widget's (visible) rect, in the rect's top-left coordinates.
        let local = CGRect(x: box.minX - rect.minX, y: box.minY - rect.minY, width: box.width, height: box.height)
        guard let scene = QRArt.scene(style, box: local) else { return nil }
        let screen = await OverlayScreen.makeGPU(rect)
        await OverlayScreen.show(screen, scene)
        let object: ScreenObject = screen
        return WidgetBuild(object: object, task: nil)
    }
}
