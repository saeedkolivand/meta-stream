// Native chat widget on the GPU: each message row is rasterised once when it arrives (ChatRows.swift); stacking, the entry
// slide and the fade-out run on the GPU as functions of time. The loop only decides WHICH rows to show.
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
        // Usually the render already is the box: skip the second CPU pass (only a box off the canvas needs clipping).
        return OverlayRaster.direct(cg, box: box, canvas: canvas)
            ?? OverlayRaster.render(box, canvas: canvas) { UIImage(cgImage: cg).draw(in: $0) }
    }

    /// Sleep length that doubles when the phone is hot, same backoff as the browser snapshot loop.
    static func pause(_ ms: Int) -> Duration {
        let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        return .milliseconds(hot ? ms * 2 : ms)
    }
}

/// Chat burst: many messages arriving at once. The widget then skips the entry slide (rows just appear).
enum ChatBurst {
    // ponytail: 3 messages within 1 s counts as a burst. Rows no longer coalesce: each costs one raster either way.
    static let messages = 3
    static let window: TimeInterval = 1

    static func isBurst(_ times: [Date], now: Date) -> Bool {
        times.lazy.filter { now.timeIntervalSince($0) <= window }.count >= messages
    }
}

/// Raster timing for the log: one "perf" line per 10 s, only when a row was rasterised.
private struct ChatRenderStats {
    private var since = Date()
    private var count = 0
    private var total = 0.0
    private var peak = 0.0

    mutating func add(rows: Int, ms: Double) { count += rows; total += ms; peak = max(peak, ms) }

    mutating func flush(now: Date, burst: Bool) {
        guard now.timeIntervalSince(since) >= 10 else { return }
        if count > 0 {
            applog("perf", "chat widget: \(count) row rasters/10s, avg \(String(format: "%.1f", total / Double(count))) ms/row, "
                + "max pass \(String(format: "%.1f", peak)) ms, burst \(burst ? "on" : "off")")
        }
        self = ChatRenderStats()
    }
}

extension OverlayCompositor {
    func chatWidget(_ l: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        guard let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        let style = ChatWidgetStyle(l.data)
        // The box inside the widget's (visible) rect, in the rect's top-left coordinates.
        let spec = ChatStackSpec(scale: box.width / max(1, style.width), origin: CGPoint(x: box.minX - rect.minX, y: box.minY - rect.minY),
                                 size: style.natural, gap: style.fontSize * 0.32, enters: style.fontSize * 0.7,
                                 fadeSeconds: Double(style.fadeSeconds), topFade: true)
        let screen = await OverlayScreen.makeGPU(rect)
        let ctx = context
        let task = Task { await ChatPlayer.run(style, spec: spec, ctx: ctx, screen: screen) }
        let object: ScreenObject = screen
        return WidgetBuild(object: object, task: task)
    }
}

/// The loop's state between passes. A pass picks the rows to show, rasterises the new ones and re-shows the scene only when
/// its row set (or whether it moves) changed.
@MainActor
final class ChatPlayer {
    private let style: ChatWidgetStyle
    private let base: ChatStackSpec
    private let screen: GPUWidgetScreenObject
    private let cache = ChatRowCache()
    private var shown = "start"   // the row keys on the object and whether its scene moves; "" = blank
    private var stats = ChatRenderStats()

    init(_ style: ChatWidgetStyle, spec: ChatStackSpec, screen: GPUWidgetScreenObject) {
        self.style = style
        base = spec
        self.screen = screen
    }

    static func run(_ style: ChatWidgetStyle, spec: ChatStackSpec, ctx: WidgetContext, screen: GPUWidgetScreenObject) async {
        let player = ChatPlayer(style, spec: spec, screen: screen)
        while !Task.isCancelled {
            if let chat = ctx.chat, let emotes = ctx.emotes { await player.pass(chat.visible, emotes) }
            try? await Task.sleep(for: WidgetRaster.pause(100))
        }
    }

    private func pass(_ visible: [ChatEvent], _ emotes: Emotes) async {
        let now = Date()
        let events = StreamChatView.rows(visible, style, now: now)
        let burst = ChatBurst.isBurst(events.filter { $0.kind == .message }.map(\.at), now: now)
        var spec = base
        if burst { spec.enters = 0 }
        let moving = ChatMotion.moving(events.map(\.at), spec, now: now)
        let before = cache.made
        let built = items(events, spec: spec, emotes: emotes, now: now)
        cache.keep(Set(built.keys))
        if cache.made > before { stats.add(rows: cache.made - before, ms: Date().timeIntervalSince(now) * 1000) }
        stats.flush(now: now, burst: burst)
        let sig = built.rows.isEmpty ? "" : built.keys.joined(separator: ";") + (moving ? "|moving" : "")
        guard sig != shown else { return }
        shown = sig
        await OverlayScreen.show(screen, built.rows.isEmpty ? nil : ChatScene.make(built.rows, spec, moving: moving))
    }

    /// The rows to show now with their rasters (cached per message), and the keys that identify them.
    private func items(_ events: [ChatEvent], spec: ChatStackSpec, emotes: Emotes, now: Date) -> (rows: [ChatRowItem], keys: [String]) {
        let channel = UserDefaults.standard.string(forKey: "chatChannel") ?? ""
        let host = StreamChatView(events: [], style: style, emotes: emotes, channel: channel, now: now, burst: true)
        let width = style.width - 2 * spec.pad
        var rows: [ChatRowItem] = []
        var keys: [String] = []
        for (index, e) in events.enumerated() {
            // ponytail: only the newest rows play animated emotes (10 fps: a fresh raster of that row per tick); others hold frame 0.
            let animate = e.kind == .message && index >= events.count - StreamChatView.animatedRows && emotes.animates(e.text)
            let frame = animate ? "|\(Int(now.timeIntervalSinceReferenceDate * 10))" : ""
            let key = ChatRowCache.key(e) + "|" + Self.emoteState(e, emotes) + frame
            keys.append(key)
            let made = cache.item(key, born: e.at, scale: spec.scale, pad: spec.pad) { host.row(e, animate: animate).frame(width: width) }
            if let row = made { rows.append(row) }
        }
        return (rows, keys)
    }

    /// "emotes in the text . how many of them have loaded": a row is rasterised again when a late emote lands.
    private static func emoteState(_ e: ChatEvent, _ emotes: Emotes) -> String {
        guard e.kind == .message else { return "" }
        let urls = Emotes.tokenize(e.text, byName: emotes.byName).compactMap { run -> URL? in
            if case .emote(let url) = run { return url }
            return nil
        }
        return "\(urls.count).\(urls.filter { emotes.images[$0] != nil }.count)"
    }
}
