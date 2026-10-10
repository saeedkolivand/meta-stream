// App side of the Live Activity: starts it when the stream is actually live, keeps it current, ends it in
// stopLive(). Streamer calls sync() from its 1 s tick, end() from stopLive() and attach() from init.
// Without the widget extension in the build (see liveactivity.yml) Activity.request fails; we log it once.
import ActivityKit
import Foundation

/// Pure push decision, split out so the throttle is unit-testable.
enum LiveActivityPolicy {
    static let kbpsInterval: TimeInterval = 15

    /// Phase, source, drops and mute changes go out immediately; a bare kbps change at most every 15 s.
    static func shouldPush(old: StreamActivityAttributes.ContentState?, new: StreamActivityAttributes.ContentState,
                           lastPushAt: Date?, now: Date) -> Bool {
        guard let old else { return true }
        var sameKbps = old
        sameKbps.kbps = new.kbps
        if sameKbps != new { return true }
        guard old.kbps != new.kbps else { return false }
        guard let lastPushAt else { return true }
        return now.timeIntervalSince(lastPushAt) >= kbpsInterval
    }
}

@MainActor
final class LiveActivityController {
    private var activity: Activity<StreamActivityAttributes>?
    private var last: StreamActivityAttributes.ContentState?
    private var lastPushAt: Date?
    private var gaveUp = false   // request failed or activities are off: don't retry (and re-log) every tick

    /// Registers the button actions and clears activities left by a previous process (a crash or kill
    /// leaves the card on the Lock Screen with a dead timer).
    func attach(_ streamer: Streamer) {
        StreamActivityActions.stop = { [weak streamer] in streamer?.stopLive() }
        StreamActivityActions.toggleMute = { [weak streamer] in if let streamer { streamer.setMuted(!streamer.muted) } }
        Task {
            for stale in Activity<StreamActivityAttributes>.activities { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Nil until the session is actually live (liveSince is set on the first successful connect).
    private func state(of streamer: Streamer) -> StreamActivityAttributes.ContentState? {
        guard let since = streamer.liveSince else { return nil }
        let phase = streamer.connectedSince == nil ? "reconnecting" : "live"
        return StreamActivityAttributes.ContentState(phase: phase, liveSince: since, kbps: streamer.kbps,
                                                     source: streamer.source, drops: streamer.drops, muted: streamer.muted)
    }

    func sync(_ streamer: Streamer) {
        guard !gaveUp, let new = state(of: streamer) else { return }
        let now = Date()
        guard LiveActivityPolicy.shouldPush(old: last, new: new, lastPushAt: lastPushAt, now: now) else { return }
        last = new
        lastPushAt = now
        let content = ActivityContent(state: new, staleDate: nil)
        if let activity {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                activity = try Activity.request(attributes: StreamActivityAttributes(), content: content)
                applog("stream", "live activity started")
            } catch {
                gaveUp = true
                applog("stream", "live activity request failed: \(error.localizedDescription)", error: true)
            }
        } else {
            gaveUp = true
            applog("stream", "live activities disabled in Settings")
        }
    }

    func end() {
        if let activity, var final = last {
            final.phase = "ended"
            final.endedAt = Date()
            let content = ActivityContent(state: final, staleDate: nil)
            Task { await activity.end(content, dismissalPolicy: .default) }
        }
        activity = nil; last = nil; lastPushAt = nil; gaveUp = false
    }
}
