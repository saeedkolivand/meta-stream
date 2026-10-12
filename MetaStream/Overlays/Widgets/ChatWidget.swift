// Native chat widget: one bitmap, re-rendered only when the chat, the loaded emotes or an in-progress fade changes.
import HaishinKit
import SwiftUI
import UIKit

/// Shared by the widget builders: SwiftUI view -> output-px bitmap, and the thermal-aware tick length.
@MainActor
enum WidgetRaster {
    /// ImageRenderer scale = output px per view point, so the bitmap lands at box size with no resampling.
    static func piece<V: View>(_ view: V, natural: CGSize, box: CGRect, canvas: CGSize) -> OverlayPiece? {
        guard natural.width > 0 else { return nil }
        let r = ImageRenderer(content: view)
        r.scale = box.width / natural.width
        r.isOpaque = false
        guard let cg = r.cgImage else { return nil }
        return OverlayRaster.render(box, canvas: canvas) { UIImage(cgImage: cg).draw(in: $0) }
    }

    /// Sleep length that doubles when the phone is hot, same backoff as the browser snapshot loop.
    static func pause(_ ms: Int) -> Duration {
        let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        return .milliseconds(hot ? ms * 2 : ms)
    }
}

extension OverlayCompositor {
    func chatWidget(_ l: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        guard let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        let style = ChatWidgetStyle(l.data)
        let natural = CGSize(width: CGFloat(style.width), height: CGFloat(style.height))
        let ctx = context
        let o = await OverlayScreen.makeImage(rect, nil)
        let task = Task {
            var last = ""
            var entering = false
            while !Task.isCancelled {
                if let chat = ctx.chat, let emotes = ctx.emotes {
                    let now = Date()
                    let rows = StreamChatView.rows(chat.recent, style, now: now)
                    // Time only enters the signature while something moves: ~20 fps for a new row's 0.32 s entry,
                    // 4 fps inside a fade-out ramp. Otherwise the picture is static and never re-rendered.
                    entering = rows.contains { StreamChatView.appear($0, now: now) < 1 }
                    let ramping = rows.contains { StreamChatView.opacity($0, style, now: now) < 1 }
                    let t = now.timeIntervalSinceReferenceDate
                    let sig = "\(chat.serial)|\(rows.count)|\(emotes.images.count)|\(entering ? Int(t * 20) : ramping ? Int(t * 4) : 0)"
                    if sig != last {
                        last = sig
                        let piece = rows.isEmpty ? nil : WidgetRaster.piece(
                            StreamChatView(events: chat.recent, style: style, emotes: emotes,
                                           channel: UserDefaults.standard.string(forKey: "chatChannel") ?? "", now: now),
                            natural: natural, box: box, canvas: canvas)
                        await OverlayScreen.setImage(o, piece?.bitmap)
                    }
                }
                try? await Task.sleep(for: WidgetRaster.pause(entering ? 50 : 200))
            }
        }
        let object: ScreenObject = o
        return WidgetBuild(object: object, task: task)
    }
}
