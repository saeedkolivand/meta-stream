// OBS transform -> canvas rectangle, then the OBS canvas (1920x1080) -> the stream output.
import CoreGraphics

private let left = 1, right = 2, top = 4, bottom = 8   // OBS alignment bit flags

/// Where the OBS canvas sits in the output: uniform scale, centered (letterboxed).
struct Fit: Sendable, Equatable {
    var scale: CGFloat
    var offX: CGFloat
    var offY: CGFloat

    func apply(_ b: CGRect) -> CGRect {
        CGRect(x: offX + b.minX * scale, y: offY + b.minY * scale, width: b.width * scale, height: b.height * scale)
    }
}

func overlayFit(canvasW: Int, canvasH: Int, outW: CGFloat, outH: CGFloat) -> Fit {
    let s = min(outW / CGFloat(canvasW), outH / CGFloat(canvasH))
    return Fit(scale: s, offX: (outW - CGFloat(canvasW) * s) / 2, offY: (outH - CGFloat(canvasH) * s) / 2)
}

private func anchor(_ pos: CGFloat, _ size: CGFloat, _ align: Int, _ lo: Int, _ hi: Int) -> CGFloat {
    if align & lo != 0 { return pos }
    if align & hi != 0 { return pos - size }
    return pos - size / 2
}

private func inside(_ start: CGFloat, _ outer: CGFloat, _ inner: CGFloat, _ align: Int, _ lo: Int, _ hi: Int) -> CGFloat {
    if align & lo != 0 { return start }
    if align & hi != 0 { return start + outer - inner }
    return start + (outer - inner) / 2
}

/// The item's rectangle in OBS canvas px for a source of natural size nw x nh (already cropped), per OBS transform rules.
func overlayPlace(_ l: OverlayLayer, _ nw: CGFloat, _ nh: CGFloat) -> CGRect {
    let w0 = nw * l.sx
    let h0 = nh * l.sy
    guard l.boundsType != 0, l.bw > 0, l.bh > 0, nw > 0, nh > 0 else {
        return CGRect(x: anchor(l.x, w0, l.align, left, right), y: anchor(l.y, h0, l.align, top, bottom), width: w0, height: h0)
    }
    let rx = l.bw / nw
    let ry = l.bh / nh
    // OBS bounds types: 1 stretch, 2 scale inner, 3 scale outer, 4 to width, 5 to height, 6 max only.
    // ponytail: "outer" (cover) is drawn as inner, since a screen object can't clip to the bounds box.
    let k: (x: CGFloat, y: CGFloat)
    switch l.boundsType {
    case 1: k = (rx, ry)
    case 2, 3: k = (min(rx, ry), min(rx, ry))
    case 4: k = (rx, rx)
    case 5: k = (ry, ry)
    default: k = (min(1, min(rx, ry)), min(1, min(rx, ry)))
    }
    let w = nw * k.x
    let h = nh * k.y
    let bx = anchor(l.x, l.bw, l.align, left, right)
    let by = anchor(l.y, l.bh, l.align, top, bottom)
    return CGRect(x: inside(bx, l.bw, w, l.boundsAlign, left, right), y: inside(by, l.bh, h, l.boundsAlign, top, bottom), width: w, height: h)
}

// MARK: in-app widgets

/// Output rect of a widget: s = layout.scale * min(canvas.w, canvas.h) / 1080; size = natural * s;
/// anchor point = (col * W/2, row * H/2); origin = anchorPoint - (col * w/2, row * h/2) + (dx * W, dy * H).
func widgetRect(_ layout: WidgetLayout, natural: CGSize, canvas: CGSize) -> CGRect {
    let s = layout.scale * min(canvas.width, canvas.height) / 1080
    let w = natural.width * s, h = natural.height * s
    let a = min(max(layout.anchor, 0), 8)
    let col = CGFloat(a % 3), row = CGFloat(a / 3)
    return CGRect(x: col * (canvas.width - w) / 2 + layout.dx * canvas.width,
                  y: row * (canvas.height - h) / 2 + layout.dy * canvas.height, width: w, height: h)
}

/// Inverse: the layout (nearest anchor by the rect's centre: thirds of the canvas) that reproduces `rect` at `scale`.
func widgetLayout(for rect: CGRect, natural: CGSize, canvas: CGSize, scale: CGFloat) -> WidgetLayout {
    guard canvas.width > 0, canvas.height > 0 else { return WidgetLayout(scale: scale) }
    func third(_ v: CGFloat, _ total: CGFloat) -> Int { v < total / 3 ? 0 : v < total * 2 / 3 ? 1 : 2 }
    let col = third(rect.midX, canvas.width), row = third(rect.midY, canvas.height)
    return WidgetLayout(anchor: row * 3 + col,
                        dx: (rect.minX - CGFloat(col) * (canvas.width - rect.width) / 2) / canvas.width,
                        dy: (rect.minY - CGFloat(row) * (canvas.height - rect.height) / 2) / canvas.height, scale: scale)
}
