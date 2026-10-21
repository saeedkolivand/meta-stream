// In-app text widgets drawn on the GPU. The task (MainActor) re-resolves the template once a second, measures the runs
// (TextRuns.plan: text and {i:symbol} icons) and, only when the string changed, hands the GPU object a still GPUScene:
// backdrop, a blurred black copy of the runs as the shadow, then the runs. Glyphs and symbols are rasterised once per look
// by StingerCanvas (cached); placing, tinting and blurring them is Core Image work done when the frame is composited.
import CoreImage
import HaishinKit
import UIKit

extension OverlayCompositor {
    /// A text layer with an in-app layout (OBS imports keep the bitmap path in LiveTextWidget.swift). nil when blank.
    func gpuTextWidget(_ layer: OverlayLayer, layout: WidgetLayout, canvas: CGSize) async -> WidgetBuild? {
        let template = layer.data["text"] ?? ""
        guard !template.allSatisfy(\.isWhitespace) else { return nil }
        let ctx = context
        let style = TextWidgetStyle(layer.data)
        let short = min(canvas.width, canvas.height) / 1080
        let scale = layout.scale * short   // widget px per canvas px, as widgetRect scales
        func current() -> String {
            WidgetVariables.resolve(style.rotate ? Self.rotatingLine(template, seconds: style.rotateSeconds, now: Date()) : template, ctx)
        }
        /// The box follows the text (re-anchored by widgetRect, so a growing "9:59" -> "10:00" stays put) and what to draw in it.
        func place(_ text: String) -> (rect: CGRect, scene: GPUScene) {
            let px = style.size * scale
            let plan = TextRuns.plan(text.allSatisfy(\.isWhitespace) ? " " : text, face: style.face, bold: style.bold, px: px,
                                     pad: style.background ? px * 0.3 : 0)
            let rect = widgetRect(layout, natural: CGSize(width: plan.size.width / scale, height: plan.size.height / scale), canvas: canvas)
            return (rect, Self.textScene(plan, style, shadowScale: short))
        }
        let start = current()
        let first = place(start)
        let widget = await OverlayScreen.makeGPU(first.rect)
        // With the Fade transition the stills step in over ~180 ms; the GPU text eases in over the same time.
        let fade = OverlayStore.shared.transition == "fade"
        await OverlayScreen.show(widget, fade ? Self.fadingIn(first.scene) : first.scene)
        let task = Task {
            if fade {
                try? await Task.sleep(for: .milliseconds(200))
                await OverlayScreen.show(widget, first.scene)   // settled: back to a still scene, no per-frame redraw
            }
            let wantsLocation = WidgetVariables.needsLocation(template)
            let wantsSpotify = WidgetVariables.needsSpotify(template)
            if wantsLocation { WidgetLocation.shared.retain() }
            if wantsSpotify { SpotifyNowPlaying.shared.retain() }
            defer {
                if wantsLocation { WidgetLocation.shared.release() }
                if wantsSpotify { SpotifyNowPlaying.shared.release() }
            }
            var shown = start
            var rect = first.rect
            while !Task.isCancelled {
                try? await Task.sleep(for: WidgetRaster.pause(1000))
                let now = current()
                guard now != shown, !Task.isCancelled else { continue }
                shown = now
                let next = place(now)
                if next.rect != rect { await OverlayScreen.move(widget, to: next.rect) }
                rect = next.rect
                await OverlayScreen.show(widget, next.scene)
            }
        }
        let object: ScreenObject = widget
        return WidgetBuild(object: object, task: task)
    }

    /// `still` fading in from nothing over 0.18 s, then held.
    nonisolated static func fadingIn(_ still: GPUScene) -> GPUScene {
        GPUScene(draw: { paper, time in
            let image = still.draw(paper, time)
            return time >= 0.18 ? image : paper.opacity(image, max(0, time / 0.18))
        }, moving: true)
    }

    /// The still scene for `plan`. The shadow is today's (offset 0,2 / blur 4 / black 80%, at 1080 scale) as a GPU recipe.
    nonisolated static func textScene(_ plan: TextPlan, _ style: TextWidgetStyle, shadowScale unit: CGFloat) -> GPUScene {
        GPUScene(draw: { paper, _ in
            var layers: [CIImage] = []
            if style.background {   // ponytail: square corners, as the bitmap path drew them
                layers.append(paper.fill(paper.bounds, style.backgroundColor))
            }
            if style.shadow {
                let dark = paper.stack(paper.txtRuns(plan, style, color: 0xFF00_0000))
                let soft = paper.opacity(paper.blur(dark, 2 * unit), 0.8)
                layers.append(soft.transformed(by: CGAffineTransform(translationX: 0, y: 2 * unit)))
            }
            layers.append(contentsOf: paper.txtRuns(plan, style, color: style.color))
            return paper.stack(layers)
        })
    }
}

extension StingerCanvas {
    /// Each run of `plan` as an image in `argb`, left to right.
    func txtRuns(_ plan: TextPlan, _ style: TextWidgetStyle, color argb: UInt32) -> [CIImage] {
        plan.items.map { item -> CIImage in
            let mid = CGPoint(x: item.x + item.width / 2, y: item.midY)
            switch item.run {
            case .text(let str):
                return text(str, at: mid, size: plan.px, weight: style.bold ? .bold : .regular, color: argb, tracking: 0, face: style.face)
            case .icon(let name):
                return symbol(name, pointSize: plan.px, color: argb, at: mid)
            }
        }
    }
}
