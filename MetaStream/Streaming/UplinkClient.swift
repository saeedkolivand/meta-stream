// Uplink transport: RTMP/SRT enum, session start, connection supervision with backoff.
import Foundation
import AVFoundation
import CoreMedia
import UIKit
import VideoToolbox
import HaishinKit
import RTMPHaishinKit
import SRTHaishinKit

extension Streamer {

    // ponytail: an enum beats a protocol here. RTMPStream and SRTStream already share
    // StreamConvertible for append/settings/bitrate and diverge only on connect/publish/close/
    // connected, so four switches cost less than an abstraction over two actor types.
    enum Uplink: Sendable {
        case rtmp(RTMPConnection, RTMPStream)
        case srt(SRTConnection, SRTStream)

        static func make(for url: String) -> Uplink {
            if url.lowercased().hasPrefix("srt://") {
                let c = SRTConnection()
                return .srt(c, SRTStream(connection: c))
            }
            let c = RTMPConnection()      // advertises hvc1 in the enhanced-RTMP connect by default
            return .rtmp(c, RTMPStream(connection: c))
        }

        var isSRT: Bool { if case .srt = self { return true }; return false }

        func connect(_ url: String) async throws {
            switch self {
            case .rtmp(let c, _): _ = try await c.connect(url)
            case .srt(let c, _): try await c.connect(URL(string: url))   // SRT takes a URL, not a String
            }
        }

        /// SRT has no publish name — the stream key rides in the URL's `streamid` query item.
        func publish(_ key: String) async throws {
            switch self {
            case .rtmp(_, let st): _ = try await st.publish(key)
            case .srt(_, let st): await st.publish()
            }
        }

        var connected: Bool {
            get async {
                switch self {
                case .rtmp(let c, _): return await c.connected
                case .srt(let c, _): return await c.connected
                }
            }
        }

        func close() async {
            switch self {
            case .rtmp(let c, _): try? await c.close()
            case .srt(let c, _): await c.close()                         // SRT's close doesn't throw
            }
        }

        func append(_ sb: CMSampleBuffer) async {
            switch self {
            case .rtmp(_, let st): await st.append(sb)
            case .srt(_, let st): await st.append(sb)
            }
        }

        /// The underlying stream as a MediaMixerOutput -- both RTMPStream and SRTStream default their own
        /// videoTrackId/audioTrackId to UInt8.max (checked HaishinKit 2.1.0/2.2.5 source: HaishinKit's own
        /// MTHKView/PiPHKView preview views do too, alongside a stream, as the documented way to tap the
        /// mixer's composited output from more than one place -- addOutput/removeOutput just append/remove
        /// from a plain array and every dispatch site loops `for output in outputs where videoTrackId == ...`,
        /// so registering this next to LayerSink is not a collision). Used by wireMixer() below to swap which
        /// stream is registered when goLive() rebuilds `uplink` for a new session.
        var output: any MediaMixerOutput {
            switch self {
            case .rtmp(_, let st): return st
            case .srt(_, let st): return st
            }
        }

        func setBitRateStrategy(_ s: some StreamBitRateStrategy) async {
            switch self {
            case .rtmp(_, let st): await st.setBitRateStrategy(s)
            case .srt(_, let st): await st.setBitRateStrategy(s)
            }
        }

        var videoSettings: VideoCodecSettings {
            get async {
                switch self {
                case .rtmp(_, let st): return await st.videoSettings
                case .srt(_, let st): return await st.videoSettings
                }
            }
        }

        func setAudioSettings(_ a: AudioCodecSettings) async {
            switch self {
            case .rtmp(_, let st): try? await st.setAudioSettings(a)
            case .srt(_, let st): try? await st.setAudioSettings(a)
            }
        }

        /// RTMP-only diagnostic: every NetConnection.*/NetStream.* status the server sends.
        /// SRT has no equivalent, so this simply returns for an SRT uplink.
        func logStatus() async {
            guard case .rtmp(let c, _) = self else { return }
            for await st in await c.status { applog("stream", "rtmp status: \(st.code) \(st.description)") }
        }

        func setVideoSettings(_ v: VideoCodecSettings) async {
            switch self {
            case .rtmp(_, let st): try? await st.setVideoSettings(v)
            case .srt(_, let st): try? await st.setVideoSettings(v)
            }
        }
    }

    /// libsrt defaults latency to ~120 ms, tuned for clean links; a phone walking through a city needs
    /// far more buffer. Applied only if the user hasn't set it themselves in the URL.
    static func withSRTLatency(_ url: String, ms: Int) -> String {
        guard url.lowercased().hasPrefix("srt://"), !url.lowercased().contains("latency=") else { return url }
        return url + (url.contains("?") ? "&" : "?") + "latency=\(ms)"
    }

    /// Phone-camera frames flow mixer → encoder → RTMP stream (and → preview view). sink/startRunning() are
    /// wired once, on first need (HaishinKit's own startRunning() no-ops on a repeat call regardless -- checked
    /// both tags); the uplink's own stream is re-registered every call whenever `uplink` itself has changed.
    func wireMixer() async {
        if wiredUplinkOutput !== uplink.output {
            if let old = wiredUplinkOutput { await mixer.removeOutput(old) }
            await mixer.addOutput(uplink.output)
            wiredUplinkOutput = uplink.output
            // mixerOut (see Hot/LayerSink) alone can't catch a repeat of the bug above: LayerSink is wired
            // once and stays wired regardless, so it keeps counting normally even in a session whose uplink
            // stream was never registered. This line is what makes THAT specific failure grep-able per session.
            applog("stream", "mixer output wired to current uplink stream")
        }
        guard !mixerWired else { return }
        mixerWired = true
        await mixer.addOutput(sink)
        await mixer.addOutput(faceCamFrames)
        await mixer.startRunning()
    }

    // MARK: RTMP

    /// bitrateKbps applies to what HaishinKit encodes (phone camera, black frames); the glasses set their own HEVC bitrate.
    /// codec: "hevc" passes the glasses' stream through untouched (YouTube, Restream, own relay);
    /// "h264" decodes and re-encodes on the phone (Kick, Twitch without Affiliate). Phone-camera video follows the same choice.
    func goLive(url: String, key: String, micUID: String, fallbackPosition: AVCaptureDevice.Position, bitrateKbps: Int = 4000, codec: String = "hevc", srtLatencyMs: Int = 2000, quality: PhoneQuality = .init()) {
        // Dual camera is decided once per session (the capture-session mode can't change live) and caps the
        // phone geometry: two simultaneous captures + a composite + an encode is what a phone can sustain at
        // 1080p30, not at 4K/60.
        dualLocked = UserDefaults.standard.bool(forKey: "dualCam")
        dualCamHidden = false
        dualCamSwapped = false
        let quality = capped(quality)
        applog("stream", "phone quality \(quality.height)p @\(quality.fps) landscape=\(quality.landscape) dual=\(dualLocked == true)")
        // Scheme picks the transport: srt:// goes out over SRT, everything else over RTMP(S).
        // Rebuilt per session so switching ingest between streams doesn't need an app restart.
        phoneQuality = quality
        let url = Self.withSRTLatency(url, ms: srtLatencyMs)
        uplink = Uplink.make(for: url)
        applog("stream", "uplink = \(uplink.isSRT ? "srt" : "rtmp")")
        // An explicit camera pick from the source picker outranks the Settings fallback preference:
        // that setting only says which camera to fall back TO when the glasses drop, so applying it
        // here was silently flipping a deliberate "back camera" choice to front on GO LIVE.
        if manualSource != "back", manualSource != "front", manualSource != "external" { self.fallbackPosition = fallbackPosition }
        let h264 = codec == "h264"
        // ponytail: adaptive bitrate's real gate is phoneEncodes ("is the phone doing the encoding"), not
        // codec == h264 — h264 always means the phone encodes, but so does hevc with the phone camera
        // driving video (source == "phone") or black frames (cameraOff). The one case with no knob is hevc
        // GLASSES PASSTHROUGH: the glasses pick their own HEVC bitrate (measured 450-600 kbps) and the phone
        // never re-encodes that video, so there's nothing to turn down. There's no headroom either — a link
        // that can't carry 600 kbps can't carry a transcode, since "helping" would mean targeting below
        // ~500 kbps, and 720x1280 at that rate is unwatchable. Do NOT auto-switch passthrough -> transcode
        // as a survival mode either: transcode needs the mixer pipeline, which silently re-imposes the PiP
        // requirement for background streaming — the streamer pockets the phone, the stream dies, and
        // nothing here tells them why.
        hot.transcoder?.invalidate()
        currentBitrateKbps = bitrateKbps          // HUD baseline; moves once phoneEncodes goes true
        bitrateCeilingKbps = bitrateKbps
        thermalCeilingKbps = nil
        cleanTicks = 0
        lastBitrateAdjustAt = nil
        hot.congested = false; hot.queueBytesOut = 0; hot.bytesOutPerSecond = 0
        // Installed regardless of codec: harmless telemetry-only capture (see QueueWatcher) even on a
        // session where phoneEncodes never goes true, and source/cameraOff can flip phoneEncodes mid-session
        // (glasses -> phone fallback) independent of the codec picked here.
        Task { [up = uplink] in await up.setBitRateStrategy(QueueWatcher(hot: hot)) }
        transcoding = h264
        if h264 {
            let mixer = self.mixer, hot = self.hot
            // Warm-up decodes to get the decoder synced to a keyframe, but nothing reaches the encoder until
            // publishing: video arriving before the publish handshake completes makes ingests drop the connection.
            // Blur (if enabled) happens once, in the mixer via syncBlurEffect() below -- not here anymore,
            // so decoded frames are never pixellated twice.
            hot.transcoder = Transcoder { sb in
                guard hot.live else { return }
                hot.appended += 1
                guard let sb = Self.retimestamped(sb) else { return }
                Task { await mixer.append(sb) }
            }
        } else {
            hot.transcoder = nil
        }

        // New session: reset the downtime/drop counters. liveSince is set once, below, on the first successful
        // connect, and is deliberately NOT reset by a reconnect — a session (GO LIVE → END LIVE) survives drops.
        downtime = 0; drops = 0; connectedSince = nil; sessionSummary = nil
        downSince = nil; escalated2m = false; escalated5m = false; backoff = 1; blurHidCamera = false
        sessionGeometryFixed = false
        warnedPhoneBattery = false; warnedThermal = false; warnedGlassesThermal = false
        startHealthMonitoring()
        reconnectTask?.cancel()

        reconnectTask = Task {
            do {
                // Meta docs: audio route must be settled before frames flow; do this before connect.
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                if let port = audioSession.availableInputs?.first(where: { $0.uid == micUID }) {
                    try audioSession.setPreferredInput(port)
                }
                try audioSession.setActive(true)

                if !muted { try await mixer.attachAudio(AVCaptureDevice.default(for: .audio)) }
                await wireMixer()

                // profileLevel containing "HEVC" flips HaishinKit's internal format to .hevc (onMetaData codec id);
                // the encoder handles phone-camera video, black frames and, in H.264 mode, the decoded glasses frames.
                // Geometry is fixed for the session: changing frame size mid-stream breaks players.
                // Glasses dictate 720x1280 at 30; the phone camera uses whatever the user configured. Gate on the
                // ACTUAL active source (`source`), not the manual preference (`manualSource`): "auto" can already
                // be sitting on the phone camera (glasses not streaming yet, or already fell back) by the time GO
                // LIVE is pressed, and manualSource == "auto" doesn't say which -- gating on manualSource silently
                // locked an auto-fallback phone session into glasses' 720x1280@30 and dropped the user's configured
                // quality (1080p60, say) any time the source pill read auto.
                // ...but `source` alone isn't enough either: stopLive() parks it on "glasses", so every session
                // after the first read "glasses" here and locked to 720x1280 portrait, then the phone camera got
                // attached (evaluateSource() on connect) into that portrait encoder -- Landscape 16:9 ignored.
                // So also count the cases where the phone is about to take over.
                let (size, rate, onPhone) = resolveSessionGeometry()
                applog("stream", "encoder \(Int(size.width))x\(Int(size.height)) @\(rate) (\(onPhone ? "phone" : "glasses"))")
                await uplink.setVideoSettings(VideoCodecSettings(
                    videoSize: size,
                    bitRate: bitrateKbps * 1000,
                    profileLevel: (h264 ? kVTProfileLevel_H264_High_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel) as String,
                    maxKeyFrameIntervalDuration: 2,
                    expectedFrameRate: Float64(rate)))
                // Re-attach with the session's quality (preset, fps, orientation): the idle attach may have run with
                // different Settings, and a portrait capture into a landscape encoder is the "still portrait" bug.
                if source == "phone" { await switchTo(glasses: false) }
                if h264 || dualLocked == true {           // decoded frames (or the face-cam composite) need the mixer → encoder → stream path
                    await wireMixer()
                    // Force the render loop off before resizing, regardless of whether stopLive()'s own
                    // teardown Task has finished yet -- goLive() must not trust that timing (see
                    // setScreenSize's doc). No-op if it's already off (the common case: blur was never on).
                    await setOffscreenMode(false)
                    await Self.setScreenSize(mixer, to: size)   // offscreen rendering (blur / face cam) must output the geometry fixed above
                    dualCamCanvas = size
                    var vm = await mixer.videoMixerSettings
                    vm.mainTrack = 0                       // track 0 straight through to the encoder
                    await mixer.setVideoMixerSettings(vm)
                    await syncBlurEffect()                 // registers blur / overlay + switches to .offscreen if already enabled
                    await pushOverlayLayout()              // the overlay may have been laid out against the idle canvas
                    hot.warm = h264
                    syncHot()                              // glasses+blur: preview switches to the (blurred) mixer output now that decode is starting
                    if onPhone {
                        // The transcoder only ever decodes GLASSES frames (see the videoFramePublisher
                        // listener in startGlasses(), the only place that calls Transcoder.decode()) -- with
                        // the phone camera driving video there is nothing to warm up and hot.transcoder.decoded
                        // can never leave 0, so this used to burn the full 8s ceiling below on every
                        // phone-camera h264 session for nothing, delaying GO LIVE by that much every time.
                        applog("stream", "phone camera driving video -- skipping decoder warm-up")
                    } else {
                        // Decode before connecting: an ingest that finds no video in its first seconds of
                        // probing treats the whole session as audio-only. Warm up, then connect with frames
                        // already flowing.
                        rtmpState = "syncing decoder…"
                        var waited = 0
                        while hot.transcoder?.decoded == 0, waited < 80 { try await Task.sleep(for: .milliseconds(100)); waited += 1 }
                        applog("stream", "decoder warm after \(waited * 100) ms, decoded=\(hot.transcoder?.decoded ?? 0)")
                    }
                }
                await uplink.setAudioSettings(AudioCodecSettings(bitRate: 96_000))

                applog("stream", "connecting to \(Self.redactedURL(url)) key=\(key.count) chars, mic=\(micUID.isEmpty ? "default" : micUID), bitrate=\(bitrateKbps), codec=\(codec)")
                Task { await Self.netProbe(url) }        // logs which interface iOS picks and whether the host answers on it
                Task { [up = uplink] in await up.logStatus() }   // RTMP server status lines; no-op on SRT

                await superviseConnection(url: url, key: key)
            } catch {
                applog("stream", "goLive setup failed: \(String(describing: error))", error: true)
                rtmpState = error.localizedDescription
                Task { [up = uplink] in await up.close() }   // drop a half-open socket so the next attempt starts clean
            }
        }
    }

    /// Connects + publishes, retrying with exponential backoff (1, 2, 4, 8 s, capped at 15 s) on any failure.
    /// Covers the FIRST connect too — nothing here gives up, so a bad initial connect retries here instead of
    /// dying in goLive's catch. Runs until stopLive() cancels reconnectTask.
    func superviseConnection(url: String, key: String) async {
        while !Task.isCancelled {
            do {
                try await connectWithTimeout(url)
                applog("stream", "connected, publishing")
                try await uplink.publish(key)

                let now = Date()
                connectedSince = now
                backoff = 1
                if let since = downSince {
                    if live {                                          // real recovery from a drop, not first connect
                        downtime += now.timeIntervalSince(since)
                        speaker?.stopRepeating(id: "rtmp", recovered: "stream back")
                        haptic(.success)
                    }
                    downSince = nil
                    escalated2m = false; escalated5m = false
                }
                rtmpState = "live"
                if !live {                                              // first-ever connect this session
                    live = true
                    liveSince = now
                    evaluateSource()
                }
            } catch {
                if Task.isCancelled { return }
                applog("stream", "connect failed: \(String(describing: error))", error: true)
                if live {
                    markDropped()
                } else {
                    if downSince == nil { downSince = Date() }          // clock starts even before ever connecting
                    rtmpState = error.localizedDescription               // surface the first-connect error
                }
                checkEscalation()
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 15)
                continue
            }

            // ponytail: poll `connected` every 2 s instead of parsing RTMPConnection status codes for the drop
            // event — the status stream above is already logged separately for diagnostics.
            while !Task.isCancelled, await uplink.connected {
                try? await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled else { return }
            markDropped()
        }
    }

    /// HaishinKit's own timeout doesn't always fire on a black-holed port; race the connect against a clock.
    func connectWithTimeout(_ url: String) async throws {
        let up = uplink
        try await withThrowingTaskGroup(of: Void.self) { g in
            g.addTask { try await up.connect(url) }
            g.addTask { try await Task.sleep(for: .seconds(12)); throw NSError(domain: "MetaStream", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not reach \(URL(string: url)?.host ?? Self.redactedURL(url)) within 12 s"]) }
            try await g.next()
            g.cancelAll()
        }
    }

    // SRT carries the stream key in the URL's streamid query item: never log it raw.
    static func redactedURL(_ url: String) -> String {
        let masked = url.replacingOccurrences(of: "(streamid=)[^&\\s]*", with: "$1***", options: [.regularExpression, .caseInsensitive])
        return redact(masked)
    }
}
