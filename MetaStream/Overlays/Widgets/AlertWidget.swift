// Native alert banner: queues follow/sub/raid/tip/cheer events from the chat feed and shows each one in turn.
// The "Island" capsule animates as ~24 fps re-renders of AlertBannerView (see AlertIsland.swift); the hold is one static frame.
import HaishinKit
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
                    queue += chat.events(since: seen).filter { style.shows($0.kind) && !$0.offensive }
                    seen = chat.serial
                    if queue.count > 20 { queue.removeFirst(queue.count - 20) }   // a raid train shouldn't queue minutes of banners
                }
                guard !queue.isEmpty else {
                    try? await Task.sleep(for: WidgetRaster.pause(200))
                    continue
                }
                let e = queue.removeFirst()
                await AlertPlayer.play(e, style: style, on: o, natural: natural, box: box, canvas: canvas)
                try? await Task.sleep(for: .seconds(AlertIsland.gap))
            }
        }
        let object: ScreenObject = o
        return WidgetBuild(object: object, task: task)
    }
}
