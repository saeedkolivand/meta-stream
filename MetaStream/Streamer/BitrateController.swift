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
            await stepBitrate(up: false, reason: "queue backlog")
            return
        }
        let throughputKbps = hot.bytesOutPerSecond * 8 / 1000
        if throughputKbps < currentBitrateKbps * 7 / 10 {   // short of target by 30%+
            cleanTicks = 0
            await stepBitrate(up: false, reason: "throughput \(throughputKbps)kbps < target \(currentBitrateKbps)kbps")
            return
        }
        cleanTicks += 1
        if cleanTicks >= 15 {
            cleanTicks = 0
            await stepBitrate(up: true, reason: "15s clean")
        }
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
        applog("stream", "bitrate \(up ? "up" : "down") -> \(next) kbps (\(reason))")
    }

    /// Pure step: 20% down (floors at floorKbps), 10% up (ceilings at ceilingKbps). No I/O, no HaishinKit —
    /// the part worth unit-testing, exercised by StreamerTests.
    static func steppedBitrate(current: Int, up: Bool, ceilingKbps: Int, floorKbps: Int) -> Int {
        let next = up ? current + current / 10 : current - current / 5
        return min(max(next, floorKbps), ceilingKbps)
    }
}
