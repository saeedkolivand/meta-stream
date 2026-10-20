// The mix's loudness: pure math (tested), the mixer output that measures it, and the HUD meter's state.
import Foundation
import AVFoundation
import CoreMedia
import HaishinKit
import os

enum AudioMath {
    static let deadAirDB: Float = -50
    static let deadAirSeconds: TimeInterval = 20

    /// RMS level of a buffer in dBFS (0 = full scale); -120 for silence. The mix is Int16 interleaved on iOS; float handled defensively.
    static func dBFS(_ b: AVAudioPCMBuffer) -> Float {
        let planes = b.format.isInterleaved ? 1 : Int(b.format.channelCount)
        let perPlane = b.format.isInterleaved ? Int(b.frameLength) * Int(b.format.channelCount) : Int(b.frameLength)
        var sum = 0.0
        if let d = b.int16ChannelData {
            for p in 0..<planes { for i in 0..<perPlane { let s = Double(d[p][i]) / 32768; sum += s * s } }
        } else if let d = b.floatChannelData {
            for p in 0..<planes { for i in 0..<perPlane { let s = Double(d[p][i]); sum += s * s } }
        } else { return -120 }
        guard planes * perPlane > 0, sum > 0 else { return -120 }
        return max(-120, Float(10 * log10(sum / Double(planes * perPlane))))
    }

    /// One dead-air step. `quietSince` is when the level first dropped below the threshold (nil while loud);
    /// alert = quiet for 20 s while live and not muted. Muted is silent on purpose, so it never alerts.
    static func deadAir(quietSince: Date?, level: Float, now: Date, live: Bool, muted: Bool) -> (quietSince: Date?, alert: Bool) {
        guard live, !muted, level < deadAirDB else { return (nil, false) }
        let since = quietSince ?? now
        return (since, now.timeIntervalSince(since) >= deadAirSeconds)
    }

    /// Settings slider (0...1) to gain.
    static func gain(_ slider: Double) -> Float { Float(min(1, max(0, slider))) }
}

/// What the HUD meter shows, plus the dead-air bookkeeping. Its own object so the ~8 Hz updates re-render only the meter, not every view watching Streamer.
@MainActor
final class AudioLevel: ObservableObject {
    @Published var db: Float = -120
    var at = Date.distantPast       // last time the mixer reported; no reports at all counts as silence
    var quietSince: Date?
    var alerting = false

    func set(_ v: Float) { db = v; at = Date() }
}

/// The latest audio clock skew, written from the audio thread, read by the Session report's recorder. Lock-protected.
enum AudioSkew {
    private static let box = OSAllocatedUnfairLock<Int?>(initialState: nil)
    static func set(_ ms: Int) { box.withLock { $0 = ms } }
    static func clear() { box.withLock { $0 = nil } }
    static var latest: Int? { box.withLock { $0 } }
}

/// Taps the mixer's final audio (track UInt8.max = what goes out) and reports the loudest buffer every ~125 ms.
final class LevelOutput: MediaMixerOutput, @unchecked Sendable {
    private let onLevel: @Sendable (Float) -> Void
    private var peak: Float = -120
    private var last = Date.distantPast
    private var lastSkewLog = Date()
    private var nextSampleTime: AVAudioFramePosition?
    init(_ onLevel: @escaping @Sendable (Float) -> Void) { self.onLevel = onLevel }
    var videoTrackId: UInt8? { nil }
    var audioTrackId: UInt8? { UInt8.max }
    func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {}
    func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        peak = max(peak, AudioMath.dBFS(buffer))
        let now = Date()
        // The mix stamps audio by counting samples (HaishinKit), video by the host clock. An external mic's own clock
        // or lost samples make this number creep over a session; a steady value is just capture latency.
        // The mix restarting its clock (a mic format change) hides drift from the skew line while the encoder keeps
        // its old offset, so flag it: after one of these, the skew numbers that follow are relative to the restart.
        if let next = nextSampleTime, when.isSampleTimeValid, when.sampleTime != next {
            applog("audio", "mix clock restarted, jumped \(Int(Double(when.sampleTime - next) / when.sampleRate * 1000)) ms")
        }
        nextSampleTime = when.isSampleTimeValid ? when.sampleTime + AVAudioFramePosition(buffer.frameLength) : nil
        if now.timeIntervalSince(lastSkewLog) >= 60, when.isHostTimeValid {
            lastSkewLog = now
            let ahead = AVAudioTime.seconds(forHostTime: when.hostTime) - AVAudioTime.seconds(forHostTime: mach_absolute_time())
            let skew = Int(ahead * 1000)
            AudioSkew.set(skew)
            applog("audio", "clock skew \(skew) ms")
        }
        guard now.timeIntervalSince(last) >= 0.125 else { return }
        last = now
        onLevel(peak)
        peak = -120
    }
    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}
}
