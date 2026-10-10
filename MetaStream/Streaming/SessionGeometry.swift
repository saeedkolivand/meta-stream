// Session geometry + phone picture: qualities, canvas math, blur/offscreen, camera controls,
// black fallback and audio inputs.
import Foundation
import AVFoundation
import CoreMedia
import UIKit
import HaishinKit

extension Streamer {

    /// What the phone camera captures and the encoder targets. Only applies while the phone is the video
    /// source: the glasses hand over 720x1280 at up to 30 fps and Meta's SDK offers third-party apps
    /// nothing higher, so these settings cannot raise that — they exist so the app is useful without glasses.
    struct PhoneQuality: Sendable {
        /// 720, 1080 or 2160 -- whichever CameraFormatCapabilities.probe() found this lens/position
        /// actually has a format for (SettingsView.CameraSettingsView drives the picker off that; this
        /// struct just carries whatever height goLive() was last called with, same as before 4K support).
        var height = 720
        var landscape = false
        var fps = 30                      // whatever CameraFormatCapabilities said this resolution supports
        /// "off" | "standard" | "cinematic" | "action". Phone camera only — the glasses stabilise in
        /// hardware and hand over already-encoded video the app never touches uncompressed.
        var stabilization = "off"

        /// Encoder frame size. Portrait is the glasses-native orientation; landscape is 16:9 for everything
        /// else. long is derived (height * 16/9), not a 720/1080-only lookup, so 4K (2160 -> 3840) falls
        /// out of the same formula rather than needing its own case.
        /// The same @AppStorage keys ContentView passes to goLive(), for attaching the camera while idle.
        static func fromDefaults() -> PhoneQuality {
            let d = UserDefaults.standard
            return PhoneQuality(height: d.object(forKey: "phoneHeight") as? Int ?? 720, landscape: d.bool(forKey: "phoneLandscape"),
                                fps: d.object(forKey: "phoneFps") as? Int ?? 30, stabilization: d.string(forKey: "phoneStabilization") ?? "off")
        }

        var size: CGSize {
            let short = CGFloat(height), long = short * 16 / 9
            return landscape ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
        }
        /// AVCaptureSession.Preset has no way to derive its name from a number -- this mapping is just
        /// that plumbing, not a capability assumption; CameraFormatCapabilities.probe (device-side) is
        /// what actually decides which of these three a given lens/position offers in Settings.
        var sessionPreset: AVCaptureSession.Preset {
            switch height {
            case 2160: return .hd4K3840x2160
            case 1080: return .hd1920x1080
            default: return .hd1280x720
            }
        }
    }

    /// The glasses' fixed output. Not configurable — see PhoneQuality.
    static let glassesSize = CGSize(width: 720, height: 1280)

    /// Whether this build can talk to glasses at all. The Meta app ID is baked in at build time from the
    /// META_APP_ID setting and is empty in a fork built without one -- someone streaming from the phone
    /// camera should not be nagged to register hardware they do not have and could never register.
    static let glassesConfigured: Bool = {
        let mwdat = Bundle.main.object(forInfoDictionaryKey: "MWDAT") as? [String: Any]
        return !((mwdat?["MetaAppID"] as? String ?? "").isEmpty)
    }()

    /// Apple's "Action mode" is Camera-app branding for the extended cinematic algorithm; AVFoundation
    /// exposes it as a stabilisation mode on the capture connection. `.cinematicExtendedEnhanced` is the
    /// strongest and needs iOS 18, so anything older falls back to `.cinematicExtended`.
    /// ponytail: sets the REQUESTED mode only — AVFoundation quietly ignores one the active format cannot
    /// do, and `activeVideoStabilizationMode` is where to look if that ever needs surfacing in the UI.
    /// nonisolated: pure String -> enum mapping, no Streamer state -- CameraFormatCapabilities.probe
    /// (CameraSettings.swift, not MainActor) calls this off the main actor to check per-format support;
    /// without this it's a Swift 6 cross-actor call error, the exact trap this file's header warns about.
    nonisolated static func stabilizationMode(_ name: String) -> AVCaptureVideoStabilizationMode {
        switch name {
        case "standard": return .standard
        case "cinematic": return .cinematic
        case "action":
            if #available(iOS 18.0, *) { return .cinematicExtendedEnhanced }
            return .cinematicExtended
        default: return .off
        }
    }

    var dualWanted: Bool { dualLocked ?? UserDefaults.standard.bool(forKey: "dualCam") }

    /// Dual camera is wanted AND this phone can run two cameras at once.
    nonisolated static var wantsMultiCam: Bool {
        UserDefaults.standard.bool(forKey: "dualCam") && AVCaptureMultiCamSession.isMultiCamSupported
    }

    func setDualCamHidden(_ hidden: Bool) {
        dualCamHidden = hidden
        applyDualCamLayout()
    }

    /// Re-applies corner/size/shape/track/visibility to the overlay window. Called from Settings' pickers and
    /// internally. Doesn't touch Screen.size, so it's safe with the render loop running.
    func applyDualCamLayout() {
        Task { await pushOverlayLayout() }
    }

    /// Overlay window rect in canvas pixels, top-left origin. short = the canvas's short side; the window is
    /// a fraction of it (S .22 / M .30 / L .40) with a 4% margin. Rounded keeps the canvas's own orientation
    /// at 16:9; circle is a square. Pure -- exercised by StreamerTests.
    nonisolated static func pipRect(canvas: CGSize, corner: String, size: String, shape: String) -> CGRect {
        let short = min(canvas.width, canvas.height)
        let f: CGFloat = size == "s" ? 0.22 : size == "l" ? 0.40 : 0.30
        let m = short * 0.04
        let w: CGFloat, h: CGFloat
        if shape == "circle" { w = short * f; h = w }
        else if canvas.height >= canvas.width { w = short * f; h = w * 16 / 9 }
        else { h = short * f; w = h * 16 / 9 }
        let x = corner.hasSuffix("Left") ? m : canvas.width - w - m
        let y = corner.hasPrefix("top") ? m : canvas.height - h - m
        return CGRect(x: x, y: y, width: w, height: h)
    }

    nonisolated static func pipCornerRadius(_ r: CGRect, shape: String) -> CGFloat {
        shape == "circle" ? r.width / 2 : min(r.width, r.height) * 0.12
    }

    /// Preview tap -> canvas pixel. The preview layer is .resizeAspect (PreviewView), so the canvas is
    /// centred and scaled to fit; a tap in the letterbox bars maps to nil. Pure -- exercised by StreamerTests.
    nonisolated static func canvasPoint(forViewPoint p: CGPoint, viewSize: CGSize, canvas: CGSize) -> CGPoint? {
        guard viewSize.width > 0, viewSize.height > 0, canvas.width > 0, canvas.height > 0 else { return nil }
        let scale = min(viewSize.width / canvas.width, viewSize.height / canvas.height)
        let ox = (viewSize.width - canvas.width * scale) / 2, oy = (viewSize.height - canvas.height * scale) / 2
        let x = (p.x - ox) / scale, y = (p.y - oy) / scale
        guard x >= 0, y >= 0, x <= canvas.width, y <= canvas.height else { return nil }
        return CGPoint(x: x, y: y)
    }

    // MARK: live camera controls (phone only -- see cameraDevice's doc)

    /// Re-applies every phone camera setting to the already-attached device via lockForConfiguration(),
    /// instead of re-attaching -- see cameraDevice's doc above. Bound to every live slider's onChange, not
    /// debounced: SwiftUI already delivers those at ~display rate, so calling this on every one already
    /// reads as immediate (this is the Camera app's own feel -- the picture changes under your finger while
    /// dragging, not on release), and a timer-based coalesce on top would only be felt as lag. `log: false`
    /// is the one concession -- see CameraSettings.apply's doc -- and costs nothing in device writes.
    func applyCameraSettings() {
        guard let device = cameraDevice else { return }
        CameraSettings.apply(CameraSettings.loadFromDefaults(), to: device, log: false)
    }

    /// Lens buttons no longer attach a different device (see CameraSettings.captureDevice(position:)'s doc
    /// -- the zoom-scale rewrite that fixed the ~6x-on-telephoto bug): one virtual device covers every
    /// lens, so "switching lens" is just setting camZoom to that lens's switch-over factor and calling
    /// applyCameraSettings() above like any other slider, no reattach. ContentView's lens buttons do this
    /// directly now; there is no Streamer-side switchLens anymore.

    /// Live stabilisation switch -- deliberately a re-attach, not a live tweak on the existing connection
    /// (unlike zoom/lens above). VideoDeviceUnit (where preferredVideoStabilizationMode actually lives --
    /// see switchTo's attachVideo configuration closure) only exists inside that closure, isolated to the
    /// mixer actor; Streamer only keeps the plain AVCaptureDevice handle afterward (see cameraDevice's
    /// doc), by design, for Swift 6 region-isolation safety (see switchTo's re-acquire comment -- that's
    /// the exact rule that broke the last build here). This HaishinKit version (2.1.0+) exposes no
    /// confirmed way to reach a live VideoDeviceUnit again post-attach (unverifiable without a build here),
    /// so this reattaches through switchTo(glasses:) instead. The framing jump this causes is expected
    /// anyway -- each stabilisation mode crops differently -- so the extra reattach glitch costs little
    /// more.
    func setStabilization(_ mode: String) {
        guard source == "phone" else { return }
        UserDefaults.standard.set(mode, forKey: "phoneStabilization")
        phoneQuality.stabilization = mode
        Task { await switchTo(glasses: false) }
    }

    /// Live mirror toggle -- same reattach reasoning as setStabilization above: isVideoMirrored also only
    /// lives on VideoDeviceUnit, set once in switchTo's attachVideo configuration closure. camMirrored is
    /// already read fresh every attach via CameraSettings.loadFromDefaults(), so writing the key and
    /// reattaching is the whole implementation.
    func setMirrored(_ mirrored: Bool) {
        guard source == "phone" else { return }
        UserDefaults.standard.set(mirrored, forKey: "camMirrored")
        Task { await switchTo(glasses: false) }
    }

    /// Long-press AE/AF lock: freezes focus and exposure at whatever they've already converged to
    /// (`.locked` mode), independently gated per Apple's docs same as tapToFocus below. Off restores the
    /// same continuous auto modes tapToFocus uses -- not whatever manual focus/exposure Settings say -- so
    /// a second long-press reads as "un-jam", not a surprise mode switch.
    /// ponytail: a reattach elsewhere (lens/stabilisation/mirror switch, or the fallback camera changing)
    /// resets focus/exposure back to CameraSettings' own modes without telling this lock go stale --
    /// ContentView clears its badge on a source change but not on an in-place reattach; add a
    /// Streamer-side published lock flag if that combination turns out to matter in practice.
    func setAEAFLocked(_ locked: Bool) {
        guard let device = cameraDevice else { return }
        do { try device.lockForConfiguration() } catch {
            applog("stream", "AE/AF lock: lockForConfiguration failed: \(error.localizedDescription)", error: true)
            return
        }
        defer { device.unlockForConfiguration() }
        if locked {
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            applog("stream", "AE/AF lock engaged")
        } else {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            applog("stream", "AE/AF lock released")
        }
    }

    /// Live "lock" reads whatever continuous auto white balance has already converged to right now and
    /// freezes there -- more useful mid-walk than picking a Kelvin value blind (see CameraSettings' type
    /// doc). Converts the sampled gains back to temperature/tint (temperatureAndTintValues(for:) is
    /// deviceWhiteBalanceGains(for:)'s documented inverse -- that forward direction is already used in
    /// CameraSettings.apply above) and writes through the exact camWBTemperature/camWBTint/
    /// camWhiteBalanceManual keys Settings' numeric fields use -- one source of truth, not a second
    /// locked-gains key -- then reapplies through the normal coalesced path. CameraSettings.apply()
    /// recomputes gains FROM those written values, which round-trips to (imperceptibly) the same lock
    /// rather than the exact gains sampled here; that's the trade for reusing one apply path instead of a
    /// bespoke lockForConfiguration call here too.
    func setWhiteBalanceLocked(_ locked: Bool) {
        let d = UserDefaults.standard
        if locked, let device = cameraDevice, device.isWhiteBalanceModeSupported(.locked) {
            let tt = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
            d.set(Double(tt.temperature), forKey: "camWBTemperature")
            d.set(Double(tt.tint), forKey: "camWBTint")
            d.set(true, forKey: "camWhiteBalanceManual")
        } else {
            d.set(false, forKey: "camWhiteBalanceManual")
        }
        applyCameraSettings()
    }

    /// Tap-to-focus/expose: independently gated on hardware support (isFocusPointOfInterestSupported /
    /// isExposurePointOfInterestSupported, per Apple's docs), continuous mode at the tapped point rather
    /// than one-shot .autoFocus/.autoExpose -- simpler than AVCam's subjectAreaDidChange-revert-to-center
    /// dance, same practical result (refocus where you tapped, keep tracking from there).
    /// ponytail: no revert-to-center on scene change; add an
    /// AVCaptureDevice.subjectAreaDidChangeNotification observer if a tap that's now stale (subject walked
    /// off) turns out to matter in practice.
    /// `point` must already be in AVCaptureDevice's point-of-interest space -- see
    /// CameraSettings.devicePoint(forViewPoint:orientation:mirrored:), the pure conversion from a preview tap.
    func tapToFocus(at point: CGPoint) {
        guard let device = cameraDevice else { return }
        do { try device.lockForConfiguration() } catch {
            applog("stream", "tap focus: lockForConfiguration failed: \(error.localizedDescription)", error: true)
            return
        }
        defer { device.unlockForConfiguration() }
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusPointOfInterest = point
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposurePointOfInterest = point
            device.exposureMode = .continuousAutoExposure
        }
        applog("stream", "tap focus/expose at \(String(format: "%.2f,%.2f", point.x, point.y))")
    }

    // MARK: audio inputs

    /// Lists inputs for the Settings picker. Called on demand (Settings opens, Go Live), never from route-change
    /// notifications: switching category fires those and looped forever.
    func refreshMics() {
        let s = AVAudioSession.sharedInstance()
        let wasPlayback = s.category == .playback
        // allowBluetoothHFP is what makes the glasses show up as an input; inputs are only listed under a record category.
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        let list = (s.availableInputs ?? []).map { Mic(id: $0.uid, name: $0.portName) }
        if wasPlayback && !live { try? s.setCategory(.playback, mode: .moviePlayback, options: []) }
        guard list != mics else { return }
        mics = list
        applog("stream", "mics: \(mics.map(\.name))")
    }

    /// Camera off = detach any phone camera, stop forwarding glasses frames, and push black frames at 15 fps
    /// so the platform keeps a live video track instead of freezing on the last picture.
    func setCameraOff(_ off: Bool) {
        cameraOff = off
        applog("stream", "cameraOff=\(off)")
        blackTask?.cancel(); blackTask = nil
        guard off else { evaluateSource(); return }
        cameraDevice = nil
        cameraCapabilities = nil
        Task {
            try? await mixer.attachVideo(nil)
            await detachOverlay()   // black frames replace the whole picture, no face cam on top of them
        }
        blackTask = Task { [weak self] in
            guard let pb = Self.blackPixelBuffer() else { return }
            var fd: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &fd)
            guard let fd else { return }
            while !Task.isCancelled, let self, self.live, self.cameraOff {
                var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 15),
                                                presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                                decodeTimeStamp: .invalid)
                var sb: CMSampleBuffer?
                CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb, formatDescription: fd, sampleTiming: &timing, sampleBufferOut: &sb)
                if let sb { await self.mixer.append(sb) }        // goes through HaishinKit's encoder like the phone camera
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
    }

    /// Rewrites a decoded glasses frame's timestamp onto the phone's own host clock before it reaches the
    /// mixer -- fixes the blur+glasses freeze (appended kept climbing, nothing came out; see mixerOut above).
    ///
    /// Checked directly in HaishinKit 2.1.0 and 2.2.5 source (Mixer/MediaMixer.swift, Screen/Screen.swift):
    /// mixer.append() always reaches Screen.append() -- track input is fed into Screen unconditionally in
    /// 2.1.0, and gated only on videoMixerSettings.mode == .offscreen (which blur sets) in 2.2.5, not on the
    /// source of the frame -- so glasses frames DO arrive at the screen either way. What actually renders
    /// them out, though, is a private displayLink loop MediaMixer starts itself: setVideoMixerSettings(_:)
    /// calls its own private setVideoRenderingMode(mode) whenever mode changes (also once from
    /// startRunning()), which is exactly what syncBlurEffect() below already triggers by flipping
    /// videoMixerSettings.mode to .offscreen -- there is no public setVideoRenderingMode to call ourselves,
    /// and the mixer already calls it. That part of a prior hypothesis for this bug does not hold up against
    /// the source and was not the fix applied here.
    ///
    /// What that private loop's Screen.makeSampleBuffer does, every displayLink tick, is reject any frame
    /// whose computed presentationTimeStamp doesn't advance past the last one it rendered -- and it computes
    /// that from the offscreen canvas's own track's sample buffer PTS compared against the displayLink's
    /// host-clock timestamp (Screen's videoCaptureLatency/targetTimestamp bookkeeping). The phone camera's
    /// CMSampleBuffers are already host-clock timestamped by AVFoundation, so that comparison is sound and
    /// blur-while-on-phone-camera renders fine (per the report: front/back camera both produce output, only
    /// back camera's fps is the separate, expected Vision-cost issue below). The glasses' CMSampleBuffers
    /// come from Meta's Wearables SDK over Bluetooth with no documented guarantee their PTS is on that same
    /// clock -- MWDATCamera is closed-source, so this is the one link in the chain not directly verifiable --
    /// and Transcoder.decode() (see Transcoder.swift, not touched here) carries that original PTS straight
    /// through the decode. A source clock that doesn't line up with the displayLink's would make the
    /// monotonic-PTS guard fail forever once it drifts behind, which matches "appended climbs, nothing comes
    /// out" exactly and explains why only the glasses path (not the phone camera, same offscreen renderer)
    /// freezes. Stamping "now" on the host clock here -- the same clock the black-frame generator below
    /// already uses, and the one AVFoundation already uses for the phone camera -- makes every source the
    /// mixer ever sees carry a PTS in that one clock domain, which is what the renderer's guard assumes.
    /// nonisolated: called synchronously from Transcoder's @Sendable sink closure (VTDecompressionSession's
    /// callback thread, not the main actor) -- a plain (implicitly MainActor) static func here would not
    /// compile without an await it cannot afford on that thread.
    nonisolated static func retimestamped(_ sb: CMSampleBuffer) -> CMSampleBuffer? {
        guard let imageBuffer = sb.imageBuffer, let fd = sb.formatDescription else { return nil }
        var timing = CMSampleTimingInfo(duration: sb.duration,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: imageBuffer, formatDescription: fd, sampleTiming: &timing, sampleBufferOut: &out)
        return out
    }

    static func blackPixelBuffer() -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 720, 1280, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        guard let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        memset(CVPixelBufferGetBaseAddress(pb), 0, CVPixelBufferGetDataSize(pb))
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }

    func setMuted(_ on: Bool) {
        muted = on
        applog("stream", "muted=\(on)")
        Task {   // ponytail: mute = detach the mic; AudioMixerSettings per-track flags avoided
            try? await mixer.attachAudio(on ? nil : AVCaptureDevice.default(for: .audio))
        }
    }

    /// Keeps the mixer's blur effect registration and rendering mode in sync with Privacy.enabled. Privacy
    /// exposes `enabled` as a plain var that ContentView sets directly (see ContentView's blur toggle) with
    /// no delegate back to Streamer, so this is polled from the 1s stats tick; goLive()'s h264 setup also
    /// calls it once up front so a session that starts with blur already on doesn't wait a full tick for its
    /// first frames to be covered. stopLive() forces the off path unconditionally (see setOffscreenMode)
    /// so a session that ends with blur on can't leave the render loop running into the next one.
    ///
    /// registerVideoEffect hooks mixer.screen (HaishinKit's offscreen render object, track 0 by default) --
    /// checked HaishinKit 2.1.0 and 2.2.5 source directly: that's the one place phone camera, black frames
    /// and (in H.264 mode) decoded glasses frames all pass through once the mixer is in .offscreen mode --
    /// 2.1.0 feeds Screen from every mixer.append/attachVideo call unconditionally, 2.2.5 gates that same
    /// feed on videoMixerSettings.mode already being .offscreen (checked both directly; this call always sets
    /// mode before frames need to arrive, so the ordering holds either way). .passthrough skips
    /// Screen/VideoTrackScreenObject rendering entirely and forwards raw buffers straight to the encoder,
    /// which is why blur silently did nothing before this. Offscreen costs more (an extra render pass), so
    /// it's only switched on while blur is actually enabled. See retimestamped() near blackPixelBuffer()
    /// above for the offscreen-mode freeze this uncovered on the glasses path specifically, and what fixed it.
    /// `Screen` lives on HaishinKit's own global actor, so its size can't be assigned from the main actor.
    /// What the offscreen canvas should be right now: the session's fixed geometry while live, otherwise
    /// whatever the phone camera is configured to produce, since that is the only thing the mixer renders
    /// before GO LIVE.
    var blurCanvasSize: CGSize { sessionGeometryFixed ? sessionVideoSize : phoneQuality.size }

    /// Dual camera caps at 1080p30: two captures + a composite + an encode is what a phone sustains, not 4K/60.
    /// UVC webcams deliver landscape 1080p30 and can't rotate the connection: portrait would squash/letterbox
    /// them, and anything past 1080p30 is just upscaling.
    func capped(_ q: PhoneQuality) -> PhoneQuality {
        var q = q
        if dualWanted || manualSource == "external" { q.height = min(q.height, 1080); q.fps = min(q.fps, 30) }
        if manualSource == "external" { q.landscape = true }
        return q
    }

    /// Screen.size reallocates the offscreen pixel-buffer pool (checked Screen.swift 2.1.0/2.2.5 directly --
    /// the `size` didSet calls CVPixelBufferPoolCreate unconditionally, no lock). The only consumer reading
    /// that pool is HaishinKit's own offscreen render loop: a Task MediaMixer spawns on this same ScreenActor
    /// from setVideoRenderingMode(.offscreen) that runs until displayLink.stopRunning() ends its AsyncStream --
    /// checked both tags directly, that's the ONLY public lever that stops it, and MediaMixer never calls it
    /// itself. So this must only run once that loop is confirmed stopped, not merely "before blur is next
    /// turned on". Getting that backwards is the relive crash (vImageCopyBuffer, the offscreen CPU renderer's
    /// only call site in either tag -- grepped both -- reached from a Task closure, matching the decoded
    /// report exactly): stopLive() used to leave mode == .offscreen whenever a session ended with blur on,
    /// so the next goLive() resized Screen.size while that session's render loop Task was still alive on this
    /// same actor. Callers rely on actor FIFO ordering: awaiting setOffscreenMode(false) first enqueues the
    /// stop on this actor ahead of the resize enqueued right after, so by the time this runs the loop has
    /// already exited -- the same ordering assumption HaishinKit's own syncBlurEffect-adjacent calls already
    /// relied on before this fix, just never stated. Not verified on-device (no build/run available here).
    @ScreenActor static func setScreenSize(_ mixer: MediaMixer, to size: CGSize) {
        guard mixer.screen.size != size else { return }   // an equal-size write would still reallocate the pool
        mixer.screen.size = size
    }

    /// The one place that flips videoMixerSettings.mode -- goLive(), stopLive() and the 1s tick (via
    /// syncBlurEffect below) all route through this instead of touching mixer.screen/videoMixerSettings
    /// directly, so there is one well-defined order instead of three callers mutating the same state
    /// independently (which is what let stopLive() and goLive() disagree about whether the render loop was
    /// still running -- see setScreenSize's doc). Offscreen is wanted by blur OR the dual-camera overlay.
    /// Turning it off also drops the blur effect first (as before). Idempotent on offscreenOn, so a
    /// redundant call (stopLive() forcing `false` when it was never on, say) costs nothing.
    func setOffscreenMode(_ on: Bool) async {
        if !on { await setBlurEffect(false) }
        guard offscreenOn != on else { return }
        offscreenOn = on
        var vm = await mixer.videoMixerSettings
        vm.mode = on ? .offscreen : .passthrough
        await mixer.setVideoMixerSettings(vm)   // starts/stops HaishinKit's offscreen render Task -- see setScreenSize's doc
        applog("stream", "mixer mode=\(vm.mode.rawValue)")
        syncHot()   // re-evaluate whether the glasses preview should now route through the (blurred/composited) mixer output
    }

    /// Registers/unregisters the privacy blur on the full-frame object only; the face-cam window is hidden
    /// instead while blur is on (see blurWanted). Independent of the mode flip above; idempotent on blurEffectActive.
    func setBlurEffect(_ on: Bool) async {
        guard let privacy, blurEffectActive != on else { return }
        blurEffectActive = on
        await Self.setPrivacyEffect(mixer, privacy: privacy, on: on)
        await pushOverlayLayout()   // the face-cam window hides while blur is on -- see blurWanted
        applog("stream", "privacy blur effect \(on ? "registered" : "unregistered")")
    }

    /// Brings the offscreen canvas, face-cam window, blur effect and render mode in line with what's wanted
    /// right now (blur enabled and/or an overlay camera attached). Polled from the 1 s tick; also called at
    /// the moments that change the answer.
    func syncBlurEffect() async {
        // Read once: `enabled` is a plain nonisolated(unsafe) var ContentView can flip mid-await.
        let blur = privacy?.enabled == true
        guard blur || dualCamActive else { await setOffscreenMode(false); return }
        if !offscreenOn {
            // Offscreen renders into Screen.size, which defaults to 1280x720 landscape. Without this a
            // portrait frame gets fitted into a landscape canvas and the picture shrinks to a stamp.
            // offscreenOn is still false here (checked above), so the render loop is confirmed stopped
            // -- safe per setScreenSize's doc.
            let canvas = blurCanvasSize
            await Self.setScreenSize(mixer, to: canvas)
            dualCamCanvas = canvas
        }
        if dualCamActive, overlayObject == nil, !makingOverlay {
            makingOverlay = true
            overlayObject = await Self.makeOverlay(mixer)
            makingOverlay = false
            await pushOverlayLayout()
        }
        await setBlurEffect(blur)
        await setOffscreenMode(true)
    }

    /// Blur failing open is worse than no blur, because the streamer is trusting it. When detection stalls
    /// we hide the picture rather than publish frames we could not obscure, and say so out loud — silence
    /// would leave someone walking down a street believing faces were still being covered. Reuses the
    /// existing black-frame path, so the HUD honestly reads "cam off" for as long as it holds.
    func checkBlurStall() {
        guard let privacy, privacy.enabled, live else { return }
        if privacy.stalled, !cameraOff {
            blurHidCamera = true
            setCameraOff(true)
            speaker?.speakSystem("blur stopped working, camera hidden")
            applog("stream", "privacy blur stalled - camera hidden", error: true)
        } else if !privacy.stalled, blurHidCamera {
            blurHidCamera = false
            setCameraOff(false)
            speaker?.speakSystem("blur working, camera back")
            applog("stream", "privacy blur recovered - camera back")
        }
    }

    // Session-fixed encoder geometry, extracted from goLive(): the phone camera uses the configured
    // quality, glasses sessions stay 720x1280. Fixes the size for the session; players break otherwise.
    func resolveSessionGeometry() -> (size: CGSize, rate: Int, onPhone: Bool) {
        let onPhone = source == "phone" || manualSource == "back" || manualSource == "front" || manualSource == "external"
            || (manualSource == "auto" && !glassesStreaming)
        let size = onPhone ? phoneQuality.size : Self.glassesSize
        let rate = onPhone ? phoneQuality.fps : 30
        sessionVideoSize = size
        sessionGeometryFixed = true
        return (size, rate, onPhone)
    }
}
