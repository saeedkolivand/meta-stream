// Native alert banner: queues follow/sub/raid/tip/cheer events from the chat feed and shows each one in turn.
// The banner is rendered once per alert; the fade is three pre-multiplied alpha copies, so a whole alert costs one
// SwiftUI render plus a handful of cheap CGContext redraws.
import SwiftUI
import UIKit

extension OverlayCompositor {
    func alertWidget(_ l: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        guard let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        let style = AlertWidgetStyle(l.data)
        let natural = CGSize(width: 900, height: 240)
        let ctx = context
        let o = await OverlayScreen.makeImage(rect, nil)
        let task = Task {
            var seen = ctx.chat?.serial ?? 0   // start from "now": a scene switch must not replay old follows
            var queue: [ChatEvent] = []
            while !Task.isCancelled {
                if let chat = ctx.chat {
                    queue += chat.events(since: seen).filter { style.shows($0.kind) }
                    seen = chat.serial
                    if queue.count > 20 { queue.removeFirst(queue.count - 20) }   // a raid train shouldn't queue minutes of banners
                }
                guard !queue.isEmpty else {
                    try? await Task.sleep(for: WidgetRaster.pause(200))
                    continue
                }
                let e = queue.removeFirst()
                guard let full = WidgetRaster.piece(AlertBannerView(event: e, style: style), natural: natural, box: box, canvas: canvas) else { continue }
                let steps: [CGFloat] = [0.33, 0.66]
                for a in steps {
                    await OverlayScreen.setImage(o, OverlayRaster.withAlpha(full.bitmap, a))
                    try? await Task.sleep(for: WidgetRaster.pause(80))
                }
                await OverlayScreen.setImage(o, full.bitmap)
                try? await Task.sleep(for: .seconds(Double(style.holdSeconds)))
                for a in steps.reversed() {
                    await OverlayScreen.setImage(o, OverlayRaster.withAlpha(full.bitmap, a))
                    try? await Task.sleep(for: WidgetRaster.pause(80))
                }
                await OverlayScreen.setImage(o, nil)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        let object: ScreenObject = o
        return WidgetBuild(object: object, task: task)
    }
}
