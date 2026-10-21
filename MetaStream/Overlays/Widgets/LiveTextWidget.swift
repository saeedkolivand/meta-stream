// Text with {tokens} (time, viewers, speed...): the string is re-resolved once a second and the bitmap redrawn only
// when it actually changed. The box follows the text size, re-anchored so a growing "9:59" -> "10:00" stays put.
import HaishinKit
import UIKit

extension OverlayCompositor {
    func liveTextWidget(_ l: OverlayLayer, canvas: CGSize) async -> WidgetBuild? {
        let template = l.data["text"] ?? ""
        guard !template.allSatisfy(\.isWhitespace) else { return nil }
        let ctx = context
        let style = TextWidgetStyle(l.data)
        func current() -> String {
            WidgetVariables.resolve(style.rotate ? Self.rotatingLine(template, seconds: style.rotateSeconds, now: Date()) : template, ctx)
        }
        let first = Self.liveText(l, current(), canvas)
        let o = await OverlayScreen.makeImage(first.visible ?? CGRect(x: 0, y: 0, width: 1, height: 1), first.piece?.bitmap)
        let task = Task {
            let wantsLocation = WidgetVariables.needsLocation(template)
            let wantsSpotify = WidgetVariables.needsSpotify(template)
            if wantsLocation { WidgetLocation.shared.retain() }
            if wantsSpotify { SpotifyNowPlaying.shared.retain() }
            defer {
                if wantsLocation { WidgetLocation.shared.release() }
                if wantsSpotify { SpotifyNowPlaying.shared.release() }
            }
            var shown = current()
            var rect = first.visible
            while !Task.isCancelled {
                try? await Task.sleep(for: WidgetRaster.pause(1000))
                let now = current()
                guard now != shown, !Task.isCancelled else { continue }
                shown = now
                let next = Self.liveText(l, now, canvas)
                if let r = next.visible, r != rect { await OverlayScreen.move(o, to: r) }
                rect = next.visible
                await OverlayScreen.setImage(o, next.piece?.bitmap)
            }
        }
        let object: ScreenObject = o
        return WidgetBuild(object: object, task: task)
    }

    /// The non-blank line of `template` shown at `now`, advancing every `seconds`; the whole template if it has no lines.
    nonisolated static func rotatingLine(_ template: String, seconds: Int, now: Date) -> String {
        let lines = template.split(separator: "\n").map(String.init).filter { !$0.allSatisfy(\.isWhitespace) }
        if lines.isEmpty { return template }
        return lines[(Int(now.timeIntervalSince1970) / max(1, seconds)) % lines.count]
    }

    /// Lays out and draws `text` for layer `l`. In-app layers (layout != nil) size from TextWidgetStyle at the
    /// widget scale, with optional shadow and rounded background; imported OBS text keeps its own transform.
    private static func liveText(_ l: OverlayLayer, _ text: String, _ canvas: CGSize) -> (piece: OverlayPiece?, visible: CGRect?) {
        let style = TextWidgetStyle(l.data)
        let shown = text.allSatisfy(\.isWhitespace) ? " " : text
        let size = CGFloat(style.size)
        func attrs(_ px: CGFloat) -> [NSAttributedString.Key: Any] {
            OverlayRaster.textAttributes(face: style.face, bold: style.bold, px: px, argb: UInt32(style.color))
        }
        let box: CGRect, a: [NSAttributedString.Key: Any], natural: CGSize, pad: CGFloat
        if let layout = l.layout {
            let s = layout.scale * min(canvas.width, canvas.height) / 1080
            a = attrs(size * s)
            natural = OverlayRaster.textSize(shown, a)
            pad = style.background ? size * s * 0.3 : 0
            let total = CGSize(width: natural.width + 2 * pad, height: natural.height + 2 * pad)
            box = widgetRect(layout, natural: CGSize(width: total.width / s, height: total.height / s), canvas: canvas)
        } else {
            let pack = OverlayStore.shared.pack
            let fit = overlayFit(canvasW: pack?.canvasW ?? Int(canvas.width), canvasH: pack?.canvasH ?? Int(canvas.height),
                                 outW: canvas.width, outH: canvas.height)
            a = attrs(size * fit.scale)
            natural = OverlayRaster.textSize(shown, a)
            pad = 0
            box = fit.apply(overlayPlace(l, natural.width / fit.scale, natural.height / fit.scale))
        }
        let inApp = l.layout != nil
        let piece = OverlayRaster.render(box, canvas: canvas) { b in
            guard let g = UIGraphicsGetCurrentContext() else { return }
            if inApp, style.background {
                OverlayRaster.fill(argb: UInt32(style.backgroundColor), in: b)   // ponytail: square corners; round them with a UIBezierPath if wanted
            }
            g.saveGState()
            if inApp, style.shadow { g.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.8).cgColor) }
            OverlayRaster.drawText(shown, a, natural: natural, in: CGRect(x: b.minX + pad, y: b.minY + pad, width: natural.width, height: natural.height))
            g.restoreGState()
        }
        return (piece, piece?.rect)
    }
}
