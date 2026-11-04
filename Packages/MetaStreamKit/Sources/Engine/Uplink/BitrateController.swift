// Adaptive bitrate: AIMD loop over the uplink queue telemetry. No-ops on HEVC passthrough.
// The decision half is a pure value (Android: streaming.uplink.BitrateController); Streamer feeds it once a second
// and applies what it returns to the uplink.
import CoreLogging
import Foundation

public struct BitrateController: Sendable {
    /// One change to apply: the new rate, its direction and why (for the Network panel ladder and the log).
    public struct Step: Sendable {
        public let kbps: Int, up: Bool, reason: String
    }

    public static let floorKbps = 500
    static let cooldown: TimeInterval = 3   // one adjustment per 3 s, so congestion + thermal together still yield one

    /// The user's configured bitrate; up-steps never exceed it.
    public let ceilingKbps: Int
    /// Live value for the HUD; == the configured target while phoneEncodes is false.
    public private(set) var currentKbps: Int
    private var thermalCeiling: Int?   // set while thermal >= .serious; caps the ceiling until it clears
    private var cleanTicks = 0         // consecutive good 1 s ticks; 15 (5 well below failedAtKbps) trigger an up-step
    private var failedAtKbps = 0       // bitrate the latest run of down-steps started from
    private var falling = false        // true from a down-step until the next up-step
    private var lastAdjust: Date?

    public init(ceilingKbps: Int, currentKbps: Int? = nil) {
        self.ceilingKbps = ceilingKbps
        self.currentKbps = currentKbps ?? ceilingKbps
    }

    /// The 1 s tick while the phone encodes and is live: down on a queue backlog or throughput 30%+ short of the
    /// target, up after enough clean seconds.
    public mutating func tick(now: Date, congested: Bool, throughputKbps: Int) -> Step? {
        if congested {
            cleanTicks = 0
            markFalling()
            return step(now, up: false, reason: "queue backlog")
        }
        if throughputKbps < currentKbps * 7 / 10 {
            cleanTicks = 0
            markFalling()
            return step(now, up: false, reason: "throughput \(throughputKbps)kbps < target \(currentKbps)kbps")
        }
        cleanTicks += 1
        let wait = Self.cleanSecondsBeforeUp(current: currentKbps, failedAt: failedAtKbps)
        guard cleanTicks >= wait else { return nil }
        cleanTicks = 0
        falling = false
        return step(now, up: true, reason: "\(wait)s clean")
    }

    /// Heat and congestion both want less bitrate, and encoding is the expensive part: serious heat forces one step
    /// down and caps the ceiling there until it clears. Edge-triggered, so it fires once per entry, not per tick.
    public mutating func thermal(now: Date, serious: Bool, reason: String) -> Step? {
        guard serious else { thermalCeiling = nil; return nil }
        guard thermalCeiling == nil else { return nil }
        thermalCeiling = currentKbps
        let forced = step(now, up: false, reason: reason)
        thermalCeiling = currentKbps
        return forced
    }

    /// The first down-step of a run remembers where the link gave out; the rest of the run keeps it.
    private mutating func markFalling() {
        if !falling { falling = true; failedAtKbps = currentKbps }
    }

    private mutating func step(_ now: Date, up: Bool, reason: String) -> Step? {
        if let lastAdjust, now.timeIntervalSince(lastAdjust) < Self.cooldown { return nil }
        let ceiling = min(thermalCeiling ?? ceilingKbps, ceilingKbps)
        let next = Self.steppedBitrate(current: currentKbps, up: up, ceilingKbps: max(ceiling, Self.floorKbps), floorKbps: Self.floorKbps)
        guard next != currentKbps else { return nil }
        currentKbps = next
        lastAdjust = now
        return Step(kbps: next, up: up, reason: reason)
    }

    /// Climbs back fast (5 s steps) while well below where the link last failed: a stall that collapses the
    /// bitrate otherwise takes minutes of 15 s steps to undo. Near or above that level, probe slowly again.
    public static func cleanSecondsBeforeUp(current: Int, failedAt: Int) -> Int {
        current < failedAt * 4 / 5 ? 5 : 15
    }

    /// Pure step: 20% down (floors at floorKbps), 10% up (ceilings at ceilingKbps).
    public static func steppedBitrate(current: Int, up: Bool, ceilingKbps: Int, floorKbps: Int) -> Int {
        let next = up ? current + current / 10 : current - current / 5
        return min(max(next, floorKbps), ceilingKbps)
    }
}

extension Streamer {
    /// Called once a second from the stats loop. Runs whenever phoneEncodes is true (h264 transcode, or hevc with
    /// the phone driving video) -- a no-op for hevc glasses passthrough, the one path with no knob (see goLive's
    /// gate comment). The network signal is HaishinKit's (QueueWatcher's telemetry off `hot`); the decision is ours.
    public func adaptBitrate() async {
        guard phoneEncodes, live else { return }
        let congested = hot.congested
        hot.congested = false
        await apply(bitrate.tick(now: .now, congested: congested, throughputKbps: hot.bytesOutPerSecond * 8 / 1000))
    }

    /// Pushes a decided step to the uplink and logs the ladder (Settings → Logs shows it after a walk).
    public func apply(_ step: BitrateController.Step?) async {
        guard let step else { return }
        var vs = await uplink.videoSettings
        vs.bitRate = step.kbps * 1000
        await uplink.setVideoSettings(vs)
        recordBitrateChange(up: step.up, kbps: step.kbps, reason: step.reason)
        applog("stream", "bitrate \(step.up ? "up" : "down") -> \(step.kbps) kbps (\(step.reason))")
    }
}
