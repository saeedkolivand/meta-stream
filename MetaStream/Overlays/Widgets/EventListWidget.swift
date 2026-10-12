// Native "recent events" list (latest follows, subs, tips, raids), newest on top. Redrawn only when the feed moves.
import SwiftUI

extension OverlayCompositor {
    func eventListWidget(_ l: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        guard let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        let style = EventListStyle(l.data)
        let natural = CGSize(width: CGFloat(style.width), height: CGFloat(style.height))
        let ctx = context
        let o = await OverlayScreen.makeImage(rect, nil)
        let task = Task {
            var last = -1
            while !Task.isCancelled {
                if let chat = ctx.chat, chat.serial != last {
                    last = chat.serial
                    let piece = EventListView.rows(chat.recent, style).isEmpty ? nil
                        : WidgetRaster.piece(EventListView(events: chat.recent, style: style), natural: natural, box: box, canvas: canvas)
                    await OverlayScreen.setImage(o, piece?.bitmap)
                }
                try? await Task.sleep(for: WidgetRaster.pause(500))
            }
        }
        let object: ScreenObject = o
        return WidgetBuild(object: object, task: task)
    }
}
