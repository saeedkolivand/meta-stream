// Native "recent events" list (latest follows, subs, tips, raids), newest on top, on the GPU: each event pill is rasterised
// once (ChatRows.swift) and the GPU stacks them. Nothing moves, so the scene is always still and is re-shown only when the
// feed changes.
import HaishinKit
import SwiftUI

extension OverlayCompositor {
    func eventListWidget(_ l: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        guard let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        let style = EventListStyle(l.data)
        // The box inside the widget's (visible) rect, in the rect's top-left coordinates.
        let spec = ChatStackSpec(scale: box.width / max(1, style.width), origin: CGPoint(x: box.minX - rect.minX, y: box.minY - rect.minY),
                                 size: style.natural, gap: 6, upward: false)
        let screen = await OverlayScreen.makeGPU(rect)
        let ctx = context
        let task = Task {
            let cache = ChatRowCache()
            var last = ""
            while !Task.isCancelled {
                if let chat = ctx.chat {
                    let events = EventListView.rows(chat.recent, style)
                    let keys = events.map(ChatRowCache.key)
                    // The serial moves with every event, but only a change in the shown rows needs a new scene.
                    if keys.joined(separator: ";") != last {
                        last = keys.joined(separator: ";")
                        let rows = Self.eventRows(events, style, spec: spec, in: cache)
                        cache.keep(Set(keys))
                        await OverlayScreen.show(screen, rows.isEmpty ? nil : ChatScene.make(rows, spec, moving: false))
                    }
                }
                try? await Task.sleep(for: WidgetRaster.pause(500))
            }
        }
        let object: ScreenObject = screen
        return WidgetBuild(object: object, task: task)
    }

    /// One raster per event (cached by key), newest first.
    private static func eventRows(_ events: [ChatEvent], _ style: EventListStyle, spec: ChatStackSpec, in cache: ChatRowCache) -> [ChatRowItem] {
        let host = EventListView(events: [], style: style)
        let width = style.width - 2 * spec.pad
        return events.compactMap { e in
            cache.item(ChatRowCache.key(e), born: e.at, scale: spec.scale, pad: spec.pad) { host.row(e).frame(width: width) }
        }
    }
}
