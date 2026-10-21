// Drives the GPU Goal widget: polls the GoalStore twice a second and hands the GPU object a still scene when the total, the
// goal or the celebration changes. A donation that raises the total plays the design's reaction as one moving scene (its t
// comes from the scene clock); the object redraws every frame only until that scene ends, then holds a still one.
import Foundation

@MainActor
enum GoalPlayer {
    private struct Context {
        let style: GoalWidgetStyle
        let screen: GPUWidgetScreenObject
        let local: CGRect
        let seconds: Double
    }

    /// What is on screen: the total and the fill it shows.
    private struct Shown {
        var total: Decimal
        var progress: Double
    }

    /// One frame's worth of numbers: the amounts the text counts between and the fill levels the bar moves between.
    private struct Span {
        var from: Decimal
        var to: Decimal
        var fromP: Double
        var toP: Double
    }

    static func run(_ style: GoalWidgetStyle, on screen: GPUWidgetScreenObject, local: CGRect) async {
        let context = Context(style: style, screen: screen, local: local, seconds: GoalDesignView.reactionSeconds(style.design))
        let store = GoalStore.shared
        var last = ""
        var wasReached = store.reached
        var reachedAt: Date?
        var shown = Shown(total: store.total, progress: store.progress)   // what the designs show; a rise above it plays a reaction
        while !Task.isCancelled {
            let cfg = store.config
            if store.reached != wasReached { wasReached = store.reached; reachedAt = store.reached ? Date() : nil }
            let celebrating = store.reached && (reachedAt.map { Date().timeIntervalSince($0) < 6 } ?? false)
            let sig = "\(store.total)|\(cfg.target)|\(cfg.title)|\(cfg.currency)|\(store.reached)|\(celebrating)"
            if sig != last {
                last = sig
                if style.design != "bar", store.total > shown.total {
                    if await react(context, &shown, celebrating: celebrating) { last = "" }
                } else {
                    shown = Shown(total: store.total, progress: store.progress)
                    await settle(context, shown, celebrating: celebrating)
                }
            }
            try? await Task.sleep(for: WidgetRaster.pause(500))
        }
    }

    private static func settle(_ context: Context, _ shown: Shown, celebrating: Bool) async {
        let span = Span(from: shown.total, to: shown.total, fromP: shown.progress, toP: shown.progress)
        let scene = GoalArt.scene(input(context.style, span, celebrating: celebrating), box: context.local)
        await OverlayScreen.show(context.screen, scene.gpu)
    }

    /// Plays the reaction from what is shown to the store's total. If the total moves again, restarts from where it is.
    /// Returns true when the total moved past what was played (the caller redraws).
    private static func react(_ context: Context, _ shown: inout Shown, celebrating: Bool) async -> Bool {
        let store = GoalStore.shared
        var span = Span(from: shown.total, to: store.total, fromP: shown.progress, toP: store.progress)
        var started = Date()
        func play() async {
            let scene = GoalArt.scene(input(context.style, span, celebrating: celebrating), box: context.local, seconds: context.seconds)
            await OverlayScreen.show(context.screen, scene.gpu)
        }
        await play()
        while !Task.isCancelled {
            let now = store.total
            if now < span.to { break }   // refund mid-reaction: the next poll redraws statically
            if now != span.to {
                let age = min(1, Date().timeIntervalSince(started) / context.seconds)
                span.fromP += (span.toP - span.fromP) * GoalMotion.move(age)
                if age >= 0.5 { span.from = span.to }
                span.to = now
                span.toP = store.progress
                started = Date()
                await play()
            }
            if Date().timeIntervalSince(started) >= context.seconds { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        shown = Shown(total: span.to, progress: span.toP)
        await settle(context, shown, celebrating: celebrating)
        return store.total != span.to
    }

    private static func input(_ style: GoalWidgetStyle, _ span: Span, celebrating: Bool) -> GoalInput {
        let store = GoalStore.shared
        let cfg = store.config
        var out = GoalInput(style: style)
        out.title = celebrating ? "Goal reached!" : cfg.title
        out.beforeText = Money(span.from, cfg.currency).display
        out.afterText = Money(span.to, cfg.currency).display
        out.targetText = Money(cfg.target, cfg.currency).display
        out.deltaText = span.to > span.from ? Money(span.to - span.from, cfg.currency).display : ""
        out.from = span.fromP
        out.to = span.toP
        out.pins = [25, 50, 75].map { Money(cfg.target * Decimal($0) / 100, cfg.currency).display }
        out.celebrating = celebrating
        let other = ["IRT", "USD", "EUR"].filter { $0 != cfg.currency }.compactMap { code in
            Rates.shared.convert(Money(span.to, cfg.currency), to: code).map { Money($0, code).display }
        }
        out.otherText = other.isEmpty ? "" : "≈ " + other.joined(separator: " · ")
        return out
    }
}
