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

/// Chat burst: many messages arriving at once. The widget then skips the entry slide and caps redraws.
enum ChatBurst {
    // ponytail: 3 messages within 1 s counts as a burst; redraws then coalesce to one per 100 ms (10 fps).
    static let messages = 3
    static let window: TimeInterval = 1
    static let minGap: TimeInterval = 0.1

    static func isBurst(_ times: [Date], now: Date) -> Bool {
        times.lazy.filter { now.timeIntervalSince($0) <= window }.count >= messages
    }
}

/// Render timing for the log: one "perf" line per 10 s, only when something rendered.
private struct ChatRenderStats {
    private var since = Date()
    private var count = 0
    private var total = 0.0
    private var peak = 0.0

    mutating func add(ms: Double) { count += 1; total += ms; peak = max(peak, ms) }

    mutating func flush(now: Date, burst: Bool) {
        guard now.timeIntervalSince(since) >= 10 else { return }
        if count > 0 {
            applog("perf", "chat widget: \(count) renders/10s, avg \(String(format: "%.1f", total / Double(count))) ms, max \(String(format: "%.1f", peak)) ms, burst \(burst ? "on" : "off")")
        }
        self = ChatRenderStats()
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
            var animating = false
            var burst = false
            var lastRender = Date.distantPast
            var stats = ChatRenderStats()
            while !Task.isCancelled {
                if let chat = ctx.chat, let emotes = ctx.emotes {
                    let now = Date()
                    let rows = StreamChatView.rows(chat.recent, style, now: now)
                    burst = ChatBurst.isBurst(rows.filter { $0.kind == .message }.map(\.at), now: now)
                    // Time only enters the signature while something moves: ~20 fps for a new row's 0.32 s entry,
                    // 4 fps inside a fade-out ramp. Otherwise the picture is static and never re-rendered.
                    // In a burst rows skip the entry slide, so nothing is "entering".
                    entering = !burst && rows.contains { StreamChatView.appear($0, now: now) < 1 }
                    let ramping = rows.contains { StreamChatView.opacity($0, style, now: now) < 1 }
                    // ponytail: animated emotes tick at 10 fps; Emotes.animates is false when the phone runs hot (frozen).
                    animating = rows.suffix(StreamChatView.animatedRows).contains { $0.kind == .message && emotes.animates($0.text) }
                    let t = now.timeIntervalSinceReferenceDate
                    let sig = "\(chat.serial)|\(rows.count)|\(emotes.images.count)|\(entering ? Int(t * 20) : animating ? Int(t * 10) : ramping ? Int(t * 4) : 0)"
                    // Burst: a change that arrives inside the gap waits; the next pass renders the latest state once.
                    if sig != last, !burst || now.timeIntervalSince(lastRender) >= ChatBurst.minGap {
                        last = sig
                        lastRender = now
                        let piece = rows.isEmpty ? nil : WidgetRaster.piece(
                            StreamChatView(events: chat.recent, style: style, emotes: emotes,
                                           channel: UserDefaults.standard.string(forKey: "chatChannel") ?? "", now: now, burst: burst),
                            natural: natural, box: box, canvas: canvas)
                        stats.add(ms: Date().timeIntervalSince(now) * 1000)
                        await OverlayScreen.setImage(o, piece?.bitmap)
                    }
                    stats.flush(now: now, burst: burst)
                }
                try? await Task.sleep(for: WidgetRaster.pause(entering ? 50 : animating || burst ? 100 : 200))
            }
        }
        let object: ScreenObject = o
        return WidgetBuild(object: object, task: task)
    }
}
