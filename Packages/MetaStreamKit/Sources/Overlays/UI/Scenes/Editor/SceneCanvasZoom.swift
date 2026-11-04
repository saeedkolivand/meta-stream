import CoreGraphics

/// Zoom and pan of the editor canvas: screen = pan + scale * view, anchored top-leading. The pan is clamped so the
/// canvas always covers the view and can never be dragged out of it.
struct CanvasZoom: Equatable {
    static let limits: ClosedRange<CGFloat> = 1...4
    var scale: CGFloat = 1
    var pan: CGSize = .zero

    var isZoomed: Bool { scale > 1.001 }

    /// A screen point (container space) in canvas view space.
    func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - pan.width) / scale, y: (point.y - pan.height) / scale)
    }

    /// A canvas view-space rect on screen.
    func toScreen(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale + pan.width, y: rect.minY * scale + pan.height, width: rect.width * scale, height: rect.height * scale)
    }

    /// This zoom after a pinch (`magnification`) and a drag (`translation`) that began at `origin`: the canvas point
    /// under `origin` stays under the fingers, then the pan is clamped to `size` (the view).
    func applying(magnification: CGFloat, translation: CGSize, origin: CGPoint, in size: CGSize) -> CanvasZoom {
        let next = min(max(scale * magnification, Self.limits.lowerBound), Self.limits.upperBound)
        let under = toView(origin)
        let rawX = origin.x + translation.width - under.x * next
        let rawY = origin.y + translation.height - under.y * next
        return CanvasZoom(scale: next, pan: CGSize(width: min(max(rawX, size.width * (1 - next)), 0),
                                                   height: min(max(rawY, size.height * (1 - next)), 0)))
    }
}
