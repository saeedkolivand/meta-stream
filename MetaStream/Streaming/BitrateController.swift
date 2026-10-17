// Adaptive bitrate: AIMD loop over the uplink queue telemetry. No-ops on HEVC passthrough.
import Foundation

extension Streamer {

    // MARK: adaptive bitrate control

    /// Called once a second from the stats loop above. Runs whenever phoneEncodes is true (h264 transcode,
    /// or hevc with the phone driving video) — a no-op for hevc glasses passthrough, the one path with no
    /// knob (see goLive's gate comment). Reads QueueWatcher's telemetry off `hot`, decides, and applies; the
    /// network signal is real (HaishinKit's own NetworkMonitor via StreamBitRateStrategy), the decision loop
    /// is ours, so it stays in lockstep with the existing 1s tick instead of a second timer.
    func adaptBitrate() async {
        guard phoneEncodes, live else { return }
        if hot.congested {
            hot.congested = false
            cleanTicks = 0
            markFalling()
            await stepBitrate(up: false, reason: "queue backlog")
            return
        }
        let throughputKbps = hot.bytesOutPerSecond * 8 / 1000
        if throughputKbps < currentBitrateKbps * 7 / 10 {   // short of target by 30%+
            cleanTicks = 0
            markFalling()
            await stepBitrate(up: false, reason: "throughput \(throughputKbps)kbps < target \(currentBitrateKbps)kbps")
            return
        }
        cleanTicks += 1
        let wait = Self.cleanSecondsBeforeUp(current: currentBitrateKbps, failedAt: failedAtKbps)
        if cleanTicks >= wait {
            cleanTicks = 0
            falling = false
            await stepBitrate(up: true, reason: "\(wait)s clean")
        }
    }

    /// The first down-step of a run remembers where the link gave out; the rest of the run keeps it.
    private func markFalling() {
        if !falling { falling = true; failedAtKbps = currentBitrateKbps }
    }

    /// Climbs back fast (5 s steps) while well below where the link last failed: a stall that collapses the
    /// bitrate otherwise takes minutes of 15 s steps to undo. Near or above that level, probe slowly again.
    static func cleanSecondsBeforeUp(current: Int, failedAt: Int) -> Int {
        current < failedAt * 4 / 5 ? 5 : 15
    }

    /// Applies one AIMD step and logs the ladder (Settings → Logs shows it after a walk). Rate-limited so
    /// congestion + thermal firing together still yields at most one change per bitrateAdjustCooldown.
    func stepBitrate(up: Bool, reason: String) async {
        if let last = lastBitrateAdjustAt, Date().timeIntervalSince(last) < bitrateAdjustCooldown { return }
        let ceiling = min(thermalCeilingKbps ?? bitrateCeilingKbps, bitrateCeilingKbps)
        let next = Self.steppedBitrate(current: currentBitrateKbps, up: up, ceilingKbps: max(ceiling, bitrateFloorKbps), floorKbps: bitrateFloorKbps)
        guard next != currentBitrateKbps else { return }
        var vs = await uplink.videoSettings
        vs.bitRate = next * 1000
        await uplink.setVideoSettings(vs)
        currentBitrateKbps = next
        lastBitrateAdjustAt = Date()
        recordBitrateChange(up: up, kbps: next, reason: reason)
        applog("stream", "bitrate \(up ? "up" : "down") -> \(next) kbps (\(reason))")
    }

    /// Pure step: 20% down (floors at floorKbps), 10% up (ceilings at ceilingKbps). No I/O, no HaishinKit —
    /// the part worth unit-testing, exercised by StreamerTests.
    static func steppedBitrate(current: Int, up: Bool, ceilingKbps: Int, floorKbps: Int) -> Int {
        let next = up ? current + current / 10 : current - current / 5
        return min(max(next, floorKbps), ceilingKbps)
    }
}
