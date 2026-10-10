// Hot frame pipeline: frame counters the SDK thread writes, mixer taps, and the glasses
// session that produces the frames, and the preview routing between them.
import Foundation
import AVFoundation
import CoreMedia
import UIKit
import HaishinKit
import MWDATCore
import MWDATCamera

/// State the SDK's frame thread reads 30×/s without hopping to the main actor. Publishing per frame made
/// SwiftUI re-render the whole screen at 30 fps (54% CPU, iOS cpu_resource report); now stats publish once a second.
// ponytail: plain vars behind @unchecked Sendable; counters can race by a frame, which the HUD can't show anyway.
final class Hot: @unchecked Sendable {
    var live = false
    var forward = true                 // source == "glasses" && !cameraOff
    var frames = 0
    var bytes = 0
    var transcoder: Transcoder?         // non-nil = decode HEVC → H.264 encoder instead of passthrough
    var warm = false                    // decoder warming up before the RTMP connect
    var sent = 0                        // glasses frames handed to the RTMP path
    var appended = 0                    // decoded frames handed to the mixer (IN)
    var mixerOut = 0                    // composited frames the mixer actually emitted (OUT) -- see LayerSink below.
                                         // appended climbing while this stalls is output starvation, not input starvation
                                         // (this is the diagnostic that would have caught the offscreen-mode freeze without a device).
    var showMixerVideo = false          // preview shows mixer output (phone camera / black) instead of glasses frames
    weak var preview: AVSampleBufferDisplayLayer?
    // Outbound-pressure telemetry for the bitrate controller (acted on only while Streamer.phoneEncodes is
    // true). Written by QueueWatcher below (HaishinKit's own NetworkMonitor callback), read once a second by
    // Streamer's existing stats loop. Same race tolerance as frames/bytes above: worst case a stale tick.
    var queueBytesOut = 0
    var bytesOutPerSecond = 0
    var congested = false               // latched by QueueWatcher on .publishInsufficientBWOccured; edge-consumed
}

/// Captures HaishinKit's NetworkMonitor reports into `hot`; does no bitrate math itself. The actual AIMD
/// decision runs in Streamer's existing 1s stats loop, not here — NetworkMonitor is `package`-scoped
/// (checked HaishinKit 2.1.0 source directly), so this StreamBitRateStrategy callback is the only public
/// door onto outbound queue/throughput. mamimumVideo/AudioBitRate are unused (we don't let this type touch
/// bitrate) but are `let`s so they're readable off-actor without await, same trick HaishinKit's own
/// StreamVideoAdaptiveBitRateStrategy uses.
actor QueueWatcher: StreamBitRateStrategy {
    let mamimumVideoBitRate = 0
    let mamimumAudioBitRate = 0
    private let hot: Hot
    init(hot: Hot) { self.hot = hot }
    func adjustBitrate(_ event: NetworkMonitorEvent, stream: some StreamConvertible) async {
        switch event {
        case .status(let report):
            hot.queueBytesOut = report.currentQueueBytesOut
            hot.bytesOutPerSecond = report.currentBytesOutPerSecond
        case .publishInsufficientBWOccured(let report):
            hot.queueBytesOut = report.currentQueueBytesOut
            hot.bytesOutPerSecond = report.currentBytesOutPerSecond
            hot.congested = true
        case .reset:
            break
        }
    }
}

/// Mirrors the mixer's video (phone camera, black frames, and -- while blur is on -- decoded glasses frames)
/// into the same preview layer the glasses use, so one layer feeds the screen and Picture in Picture whatever
/// the source is. videoTrackId == UInt8.max (not a specific track number) is deliberate: that's HaishinKit's
/// sentinel for the mixer's final rendered/composited output -- the exact same tap RTMPStream/SRTStream use
/// (checked HaishinKit 2.1.0 source: both default videoTrackId to UInt8.max) -- so this shows whatever
/// actually goes out, effects included. A specific track number instead (e.g. 0) taps the RAW per-track
/// input before Screen/effects ever see it, in every mixer mode; that was the bug that kept the local
/// preview looking clean while blur silently did nothing to it.
final class LayerSink: MediaMixerOutput, @unchecked Sendable {
    private let hot: Hot
    init(hot: Hot) { self.hot = hot }
    var videoTrackId: UInt8? { UInt8.max }
    var audioTrackId: UInt8? { nil }
    func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        hot.mixerOut += 1   // counted regardless of preview state -- this is the mixer's composited-output tap firing, full stop
        guard hot.showMixerVideo, let p = hot.preview else { return }
        if p.status == .failed { p.flush() }
        p.enqueue(sampleBuffer)
    }
    func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {}
    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}
}

/// Counts raw track-1 (face cam) frames: tells "the overlay camera delivers nothing" apart from "it delivers
/// but the composite never shows it" in the log.
final class TrackCounter: MediaMixerOutput, @unchecked Sendable {
    var count = 0
    var videoTrackId: UInt8? { 1 }
    var audioTrackId: UInt8? { nil }
    func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) { count += 1 }
    func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {}
    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}
}

// One capture box replacing the one-use FloatBox/StringBox/Once trio: value passing plus the
// single-fire gate netProbe's competing connect/timeout callbacks need.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); defer { lock.unlock() }; storage = newValue }
    }
    init(_ value: T) { storage = value }
}
extension Box where T == Bool {
    func fire() -> Bool { lock.lock(); defer { lock.unlock() }; if storage { return false }; storage = true; return true }
}

extension Streamer {

    func syncHot() {
        hot.forward = source == "glasses" && !cameraOff
        // The glasses preview normally shows the raw HEVC stream directly (AVSampleBufferDisplayLayer decodes
        // it itself -- lower latency than round-tripping through the mixer), but that raw stream can never be
        // blurred (or composited with the face cam): it never reaches the mixer (see the ADR). While glasses
        // frames are actually being decoded (warm or live, H.264 mode) with blur or dual camera on, route the
        // preview through the mixer instead, same as phone camera/black frames, so the streamer sees what's
        // actually going out rather than a clean picture that silently isn't what the audience gets. Called
        // from goLive()/stopLive()/syncBlurEffect() too, since those flip the state this depends on without
        // themselves being observed properties.
        let glassesBlurredLive = hot.forward && hot.transcoder != nil && (hot.live || hot.warm) && (privacy?.enabled == true || dualCamActive)
        let show = source == "phone" || cameraOff || glassesBlurredLive
        if show != hot.showMixerVideo { hot.showMixerVideo = show; hot.preview?.flush() }   // format switches between sources
    }

    // ponytail: ContentView sets this directly instead of a delegate protocol.
    var preview: AVSampleBufferDisplayLayer? {
        get { hot.preview }
        set { hot.preview = newValue }
    }

    // MARK: glasses

    func register() {
        Task {
            do { try await Wearables.shared.startRegistration() } catch { registration = error.localizedDescription }
        }
    }

    // Same order as Meta's CameraAccess sample: session.start() → wait for .started → addCamera → stream.start().
    func startGlasses(resolution: String = "high", fps: UInt = 30, attempt: Int = 1) {
        glassesOn = true
        Task {
            do {
                // ponytail: not branching on the returned status; createSession fails anyway if denied.
                _ = try await Wearables.shared.requestPermission(.camera)

                // The SDK fills its device list asynchronously after registration; give it up to 10 s.
                let selector = AutoDeviceSelector(wearables: Wearables.shared)
                glassesState = "looking for glasses…"
                var tries = 0
                while selector.activeDevice == nil, tries < 20 {   // ponytail: 0.5 s poll instead of racing activeDeviceStream
                    try await Task.sleep(for: .milliseconds(500)); tries += 1
                }
                guard let id = selector.activeDevice, let device = Wearables.shared.deviceForIdentifier(id) else {
                    glassesState = "no linked glasses. Open Meta AI, make sure glasses are connected, then retry"
                    glassesOn = false
                    return
                }
                switch device.compatibility() {
                case .deviceUpdateRequired:
                    glassesState = "glasses firmware too old, opening Meta AI update"
                    glassesOn = false
                    try await Wearables.shared.openFirmwareUpdate()
                    return
                case .sdkUpdateRequired:
                    glassesState = "app SDK too old for these glasses, rebuild with newer DAT"
                    glassesOn = false
                    return
                default: break
                }

                let session = try Wearables.shared.createSession(deviceSelector: selector)
                self.session = session
                tokens.append(session.statePublisher.listen { [weak self] state in
                    Task { @MainActor in
                        guard let self else { return }
                        self.glassesState = "session \(state.description)"
                        // ponytail: no HingeState to read — MWDATCore 0.9.0 has no such type (see the
                        // health-properties comment above). Meta's own AGENTS.md says folding the hinge
                        // drops Bluetooth and forces the session to .stopped, so treat .stopped as the
                        // fold proxy: skip the 2 s frame-loss debounce in evaluateSource() and switch to
                        // the phone camera right away. Never ends the broadcast — that's stopLive()'s
                        // job alone, always a separate deliberate act. Ceiling: .stopped also covers a
                        // dead battery or walking out of range, so those get the fast switch too — same
                        // desired outcome, so harmless; a real HingeState replaces this proxy outright.
                        if state == .stopped, self.manualSource == "auto", self.source == "glasses" {
                            self.fallbackTask?.cancel()
                            await self.switchTo(glasses: false)
                        }
                    }
                })
                tokens.append(session.errorPublisher.listen { [weak self] error in
                    Task { @MainActor in
                        self?.glassesState = "session error: \(error.description)"
                        if error == .datAppOnTheGlassesUpdateRequired { try? await Wearables.shared.openDATGlassesAppUpdate() }
                    }
                })
                try session.start()

                // Wait until the device link is up; addCamera returns nil before that.
                tries = 0
                while session.state != .started, tries < 60 {           // ponytail: 30 s ceiling
                    if session.state == .stopped {                        // "Device unavailable" (SDK #292) usually clears on retry
                        self.session = nil; tokens.removeAll()
                        if attempt < 3 {
                            glassesState = "glasses refused, retrying (\(attempt + 1)/3)…"
                            try await Task.sleep(for: .seconds(2))
                            startGlasses(resolution: resolution, fps: fps, attempt: attempt + 1)
                        } else {
                            glassesOn = false
                        }
                        return
                    }
                    try await Task.sleep(for: .milliseconds(500)); tries += 1
                }
                guard session.state == .started else {
                    glassesState = "session never reached started (\(session.state.description))"
                    glassesOn = false
                    return
                }

                // hvc1 = compressed HEVC, keeps delivering while the app is in the background.
                let res: StreamingResolution = resolution == "low" ? .low : resolution == "medium" ? .medium : .high
                let config = StreamConfiguration(videoCodec: .hvc1, resolution: res, frameRate: fps)
                guard let camera = try session.addCamera(config: config) else {
                    glassesState = "addCamera returned nil"
                    glassesOn = false
                    return
                }
                self.camera = camera

                tokens.append(camera.stream.statePublisher.listen { [weak self] state in
                    Task { @MainActor in
                        guard let self else { return }
                        self.glassesState = "stream \(state)"
                        self.glassesStreaming = (state == .streaming)
                        self.evaluateSource()
                    }
                })
                tokens.append(camera.stream.errorPublisher.listen { [weak self] error in
                    Task { @MainActor in
                        guard let self else { return }
                        self.glassesState = "stream error: \(error.description)"
                        self.glassesStreaming = false
                        self.evaluateSource()
                    }
                })
                let hot = self.hot, up = self.uplink
                tokens.append(camera.stream.videoFramePublisher.listen { frame in
                    // Runs on the SDK's thread. No main-actor hop: nothing here touches SwiftUI state.
                    let sb = frame.sampleBuffer
                    hot.frames += 1
                    hot.bytes += CMSampleBufferGetTotalSampleSize(sb)
                    if hot.forward, hot.live || hot.warm {
                        hot.sent += 1
                        if let t = hot.transcoder { t.decode(sb) }            // H.264 mode: decode → mixer → encoder
                        else if hot.live { Task { await up.append(sb) } }     // HEVC mode: passthrough, no encode
                    }
                    if !hot.showMixerVideo, let preview = hot.preview {       // AVSampleBufferDisplayLayer is thread-safe
                        if preview.status == .failed { preview.flush() }
                        preview.enqueue(sb)                                   // layer decodes HEVC itself
                    }
                })
                tokens.append(camera.stream.photoDataPublisher.listen { [weak self] photo in
                    Task { @MainActor in
                        if let img = UIImage(data: photo.data) {
                            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                            self?.lastPhotoAt = Date()
                        }
                    }
                })
                camera.stream.start()
            } catch DeviceSessionError.datAppOnTheGlassesUpdateRequired {
                glassesState = "glasses need the Meta app update, opening Meta AI"
                glassesOn = false
                try? await Wearables.shared.openDATGlassesAppUpdate()
            } catch {
                glassesState = error.localizedDescription
                glassesOn = false
            }
        }
    }

    func stopGlasses() {
        camera?.stream.stop()
        camera?.stop()
        session?.stop()
        camera = nil
        session = nil
        tokens.removeAll()
        glassesStreaming = false
        glassesOn = false
        glassesState = "stopped"
        evaluateSource()
    }

    func capturePhoto() {
        _ = camera?.stream.capturePhoto(format: .jpeg)
    }
}
