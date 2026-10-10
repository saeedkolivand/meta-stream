// Phone sources + overlay composition: source selection, phone/dual-camera attach, mixer mode.
import Foundation
import AVFoundation
import CoreMedia
import UIKit
import HaishinKit

extension Streamer {

    // MARK: fallback camera (StreamHand-style: glasses drop → phone camera, glasses back → glasses)

    /// "auto" = glasses with automatic phone fallback; "glasses" = force glasses; "back"/"front" = force a phone camera.
    func setSource(_ s: String) {
        let wasExternal = manualSource == "external"
        manualSource = s
        if s == "back" || s == "front" { fallbackPosition = s == "front" ? .front : .back }
        evaluateSource()
        // auto normally leaves an already-attached phone camera alone, but here that camera is the UVC
        // device we're leaving (or that just vanished) -- re-attach the phone camera unless glasses take over.
        if wasExternal, s == "auto", !glassesStreaming { Task { await switchTo(glasses: false) } }
    }

    /// First UVC camera AVFoundation exposes (iPadOS 17+ over USB-C), or nil. A fresh discovery each call so
    /// callers always get a live handle rather than one already handed to the mixer.
    nonisolated static func externalCamera() -> AVCaptureDevice? {   // nonisolated: a main-actor result can't be sent to the mixer actor (Swift 6 region isolation)
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices.first
    }

    /// Updates externalCameraName from the current device list. If the camera was unplugged while it was the
    /// chosen source, falls back to auto (glasses / phone camera) instead of leaving a dead feed -- never ends a live stream.
    func refreshExternalCamera() {
        externalCameraName = Self.externalCamera()?.localizedName
        guard externalCameraName == nil, manualSource == "external" else { return }
        applog("stream", "external camera disconnected -- falling back to auto", error: true)
        speaker?.speakSystem("external camera disconnected")
        setSource("auto")
    }

    func evaluateSource() {
        fallbackTask?.cancel()
        switch manualSource {
        case "back", "front", "external":
            Task { await switchTo(glasses: false) }     // re-attaching with the other position swaps cameras
            return
        case "glasses":
            if source == "phone" { Task { await switchTo(glasses: true) } }
            return
        default: break
        }
        if glassesStreaming {
            if source == "phone" { Task { await switchTo(glasses: true) } }
        } else if source == "glasses" {
            fallbackTask = Task { [weak self] in        // ponytail: 2 s debounce, no hysteresis
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, !self.glassesStreaming else { return }
                await self.switchTo(glasses: false)
            }
        }
    }

    func switchTo(glasses: Bool) async {
        do {
            // A swap is only meaningful against the camera pair it was made on; every re-attach starts unswapped
            // (else mainTrack could be left pointing at a track the new attach never fills).
            if dualCamSwapped { dualCamSwapped = false; await applyMainTrack() }
            if glasses {
                // Glasses video enters the mixer as decoded frames on track 0 (Transcoder), never as a capture
                // device, so the only camera here is the optional front-camera overlay on track 1.
                if dualCamActive { await detachOverlay() }
                try await mixer.attachVideo(nil)
                source = "glasses"
                cameraDevice = nil
                cameraCapabilities = nil
                if dualWanted {
                    await wireMixer()
                    if await attachOverlayCamera(position: .front) {
                        try? await mixer.setFrameRate(30)
                        await mixer.setVideoOrientation(.portrait)   // glasses canvas is 720x1280 portrait
                        dualCamActive = true
                        await syncBlurEffect()
                        logFaceCamHealth()
                    }
                }
            } else {
                // Encoded by HaishinKit in whatever geometry goLive fixed for this session, so the outgoing
                // stream never changes format even when the source switches. Phone capture pauses in the
                // background; glasses HEVC doesn't.
                // Re-read fresh on every attach (not cached) so a front/back switch re-picks the camera and
                // re-runs every capability check against the NEW device -- see CameraSettings.apply's doc.
                let camSettings = CameraSettings.loadFromDefaults()
                // External (UVC) main: unplugged between the pick and now -> drop back to auto rather than attach nothing.
                let isExt = manualSource == "external"
                if isExt, Self.externalCamera() == nil { refreshExternalCamera(); return }
                // Idle: attach with the current Settings, not whatever the last goLive() left in phoneQuality
                // (the default portrait 720p on a fresh launch -- a portrait camera in the landscape face-cam
                // canvas was the "tiny picture" bug). The canvas can only be resized with the render loop
                // stopped, so drop offscreen first when the size changes; syncBlurEffect() below re-sizes it.
                if !sessionGeometryFixed {
                    phoneQuality = capped(.fromDefaults())
                    if offscreenOn, dualCamCanvas != phoneQuality.size { await setOffscreenMode(false) }
                }
                await wireMixer()
                let multi = mixerIsMulti
                // Dual camera: plain wide lens, not the virtual triple-lens device. Paired with a second camera
                // in a multicam session, the virtual device's overlay connection silently never formed (0 face-cam
                // frames on device). Wide back + wide front is the pair Apple's own multicam sample uses.
                let wideMain = multi && dualWanted && !isExt
                let cam = isExt ? Self.externalCamera() : wideMain ? CameraSettings.device(lens: "wide", position: fallbackPosition) : CameraSettings.captureDevice(position: fallbackPosition)
                // A .single session can't hold two devices, so any leftover overlay (e.g. from the glasses
                // branch) must go before track 0 is attached; a .multi session re-attaches track 1 below.
                if dualCamActive, !(multi && dualWanted) { await detachOverlay() }
                // A multicam session can't apply presets at all -- each device's activeFormat is picked below.
                // UVC formats rarely match a preset, so an external device never gets one.
                if !multi, !isExt { await mixer.setSessionPreset(phoneQuality.sessionPreset) }
                let mode = Self.stabilizationMode(phoneQuality.stabilization)
                let mainMaxHeight = min(phoneQuality.height, 1080)
                let mcFps = min(phoneQuality.fps, 30)
                let configureMain: @Sendable (VideoDeviceUnit) throws -> Void = { unit in
                    // UVC devices expose no stabilisation, mirroring, format or camera controls: leave the
                    // camera's own default format alone.
                    if isExt { return }
                    unit.preferredVideoStabilizationMode = mode
                    unit.isVideoMirrored = camSettings.mirrored
                    if let device = unit.device {
                        if multi { Streamer.applyMultiCamFormat(device, maxHeight: mainMaxHeight, fps: mcFps) }   // before apply(): a format change resets zoom
                        CameraSettings.apply(camSettings, to: device)
                    }
                }
                try await mixer.attachVideo(cam, track: 0, configuration: configureMain)
                if isExt {
                    applog("stream", "external camera attached: \(externalCameraName ?? "unknown")")
                } else {
                    if mode != .off { applog("stream", "stabilization requested: \(phoneQuality.stabilization)") }
                    applog("stream", "camera zoom=\(String(format: "%.2f", camSettings.zoom))x position=\(fallbackPosition == .front ? "front" : "back")")
                }

                // Face-cam overlay: the OTHER position on track 1. Main always stays on track 0; swapping is
                // done on the screen side (mainTrack + overlay track), never by re-attaching.
                var overlayOK = false
                var mainIsWide = wideMain
                if dualWanted, !multi, !warnedNoMultiCam {
                    warnedNoMultiCam = true
                    applog("stream", "dual camera: this phone cannot run two cameras at once -- overlay skipped for the phone camera")
                }
                if dualWanted, multi {
                    overlayOK = await attachOverlayCamera(position: isExt ? .front : (fallbackPosition == .front ? .back : .front))
                    if overlayOK {
                        var cost = await Self.multiCamCost(mixer)
                        applog("stream", "dual camera: hardwareCost=\(String(format: "%.2f", cost))")
                        if !isExt, !mainIsWide, cost > 1.0, let wide = CameraSettings.device(lens: "wide", position: fallbackPosition) {
                            // Virtual multi-lens devices cost more than a single physical lens -- retry the main as plain wide.
                            try await mixer.attachVideo(wide, track: 0, configuration: configureMain)
                            mainIsWide = true
                            cost = await Self.multiCamCost(mixer)
                            applog("stream", "dual camera: retried main as wide lens, hardwareCost=\(String(format: "%.2f", cost))")
                        }
                        if cost > 1.0 {
                            overlayOK = false
                            await detachOverlay()
                            applog("stream", "dual camera: hardwareCost \(String(format: "%.2f", cost)) > 1.0, overlay dropped", error: true)
                            speaker?.speakSystem("face cam unavailable on this phone")
                        }
                    }
                }
                // ponytail: re-acquire rather than reuse `cam`. Swift 6 region isolation treats `cam` as
                // sent once it crosses into the mixer's domain, so touching it again here is a data race by
                // construction. AVCaptureDevice.default returns the same underlying device anyway.
                // External: no controls to drive, so ContentView's zoom/focus/lens UI has nothing to bind to.
                if isExt {
                    cameraDevice = nil
                    cameraCapabilities = nil
                } else {
                    cameraDevice = mainIsWide ? CameraSettings.device(lens: "wide", position: fallbackPosition) : CameraSettings.captureDevice(position: fallbackPosition)
                    cameraCapabilities = CameraCapabilities.probe(position: fallbackPosition)
                    cameraPosition = fallbackPosition
                }
                // UVC webcams deliver 1080p30 landscape and generally can't rotate the connection, so external
                // is always landscape and capped at 30 regardless of the quality setting.
                try? await mixer.setFrameRate(Float64(isExt || multi ? mcFps : phoneQuality.fps))
                await mixer.setVideoOrientation(isExt ? .landscapeRight : phoneQuality.landscape ? landscapeOrientation : .portrait)
                applog("stream", "camera attached \(phoneQuality.height)p @\(phoneQuality.fps) landscape=\(isExt || phoneQuality.landscape) multi=\(multi) overlay=\(overlayOK)")
                source = "phone"
                if overlayOK {
                    dualCamActive = true
                    await syncBlurEffect()
                    logFaceCamHealth()
                }
            }
        } catch {
            rtmpState = "camera switch: \(error.localizedDescription)"
        }
    }

    /// Rotation lock off: while idle, turning the phone picks the Aspect setting (portrait/landscape) and
    /// re-attaches the camera; the UI rotates with it (Info.plist). Live, the geometry is fixed for the session,
    /// so only a landscape flip to the other side is followed (same size, just which way up). Face up/down and
    /// upside down keep the current pick.
    func deviceRotated() {
        let o = UIDevice.current.orientation
        guard o.isLandscape || o == .portrait else { return }
        if o.isLandscape { landscapeOrientation = o == .landscapeLeft ? .landscapeRight : .landscapeLeft }   // device and video landscape are named opposite
        if !sessionGeometryFixed { UserDefaults.standard.set(o.isLandscape, forKey: "phoneLandscape") }
        applog("stream", "device rotated: \(o.isLandscape ? "landscape" : "portrait")")
        // Settle first: a quick turn back and forth stacked overlapping re-attaches on device.
        rotateTask?.cancel()
        rotateTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, source == "phone", manualSource != "external", !cameraOff else { return }
            if !sessionGeometryFixed, phoneQuality.landscape != o.isLandscape { await switchTo(glasses: false) }
            else if phoneQuality.landscape { await mixer.setVideoOrientation(landscapeOrientation) }
        }
    }

    /// Multicam sessions ignore sessionPreset, so resolution comes from each device's activeFormat, and it
    /// MUST be a format with isMultiCamSupported. Picks 16:9 (landscape-native dims), height <= maxHeight,
    /// supporting `fps`, preferring binned formats (cheaper for the session's hardwareCost), then the tallest.
    /// Leaves the device on its current format if nothing qualifies. nonisolated: runs inside the
    /// attachVideo configuration closure on the mixer's actor.
    nonisolated static func applyMultiCamFormat(_ device: AVCaptureDevice, maxHeight: Int, fps: Int) {
        let want = Double(fps)
        func supports(_ f: AVCaptureDevice.Format) -> Bool {
            f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= want && want <= $0.maxFrameRate }
        }
        func key(_ f: AVCaptureDevice.Format) -> (Int, Int32) {
            (f.isVideoBinned ? 1 : 0, CMVideoFormatDescriptionGetDimensions(f.formatDescription).height)
        }
        let fits = device.formats.filter { f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return f.isMultiCamSupported && Int(d.width) * 9 == Int(d.height) * 16 && Int(d.height) <= maxHeight
        }
        let pool = fits.filter(supports).isEmpty ? fits : fits.filter(supports)
        guard let best = pool.max(by: { key($0) < key($1) }), (try? device.lockForConfiguration()) != nil else { return }
        device.activeFormat = best
        if supports(best) {   // an out-of-range duration raises an ObjC exception, so only set it when the format allows it
            let d = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = d
            device.activeVideoMaxFrameDuration = d
        }
        device.unlockForConfiguration()
    }

    /// Attaches `position`'s camera on track 1 as the face-cam overlay. Never throws -- a failed overlay must
    /// not take the main camera down with it. Mirrored when it's the front camera (selfie convention),
    /// stabilisation off (it only costs latency on a thumbnail). Returns whether it attached.
    func attachOverlayCamera(position: AVCaptureDevice.Position) async -> Bool {
        guard let cam = CameraSettings.device(lens: "wide", position: position) else {   // plain wide -- see switchTo's wideMain
            applog("stream", "dual camera: no camera at that position", error: true)
            return false
        }
        let multi = mixerIsMulti
        let mirror = position == .front
        let fps = min(phoneQuality.fps, 30)
        if !multi { await mixer.setSessionPreset(.hd1280x720) }   // single-session overlay (glasses mode) has no format picker
        do {
            try await mixer.attachVideo(cam, track: 1) { unit in
                unit.preferredVideoStabilizationMode = .off
                unit.isVideoMirrored = mirror
                if multi, let device = unit.device { Streamer.applyMultiCamFormat(device, maxHeight: 720, fps: fps) }
            }
            applog("stream", "dual camera: overlay attached (\(mirror ? "front" : "back"))")
            return true
        } catch {
            applog("stream", "dual camera: overlay attach failed: \(error.localizedDescription)", error: true)
            await detachOverlay()
            return false
        }
    }

    /// Drops the overlay camera and hides its window. Also undoes a swap -- with the overlay gone, mainTrack
    /// must point back at track 0 or the stream would go black.
    func detachOverlay() async {
        try? await mixer.attachVideo(nil, track: 1)
        dualCamActive = false
        if dualCamSwapped { dualCamSwapped = false; await applyMainTrack() }
        await pushOverlayLayout()
    }

    /// Tap on the small window (phone mode): the two cameras trade places.
    func swapDualCam() {
        guard source == "phone", dualCamActive else { return }
        dualCamSwapped.toggle()
        Task { await applyMainTrack() }
    }

    /// mainTrack also drives the screen's built-in full-frame object (setVideoMixerSettings sets its track),
    /// so a swap is: full-frame -> track 1, overlay window -> track 0 (and back).
    func applyMainTrack() async {
        var vm = await mixer.videoMixerSettings
        vm.mainTrack = dualCamSwapped ? 1 : 0
        await mixer.setVideoMixerSettings(vm)
        await pushOverlayLayout()
    }

    func pushOverlayLayout() async {
        guard let o = overlayObject, dualCamCanvas.width > 0 else { return }
        let s = Self.pipSettings()
        await Self.layoutOverlay(o, canvas: dualCamCanvas, corner: s.corner, size: s.size, shape: s.shape,
                                 track: dualCamSwapped ? 0 : 1, visible: dualCamActive && !dualCamHidden && !blurWanted)
    }

    static func pipSettings() -> (corner: String, size: String, shape: String) {
        let d = UserDefaults.standard
        return (d.string(forKey: "dualCamCorner") ?? "topRight", d.string(forKey: "dualCamSize") ?? "m", d.string(forKey: "dualCamShape") ?? "rounded")
    }

    /// Blur hides the face-cam window instead of blurring it. Privacy is ONE stateful effect (frame counter,
    /// last detected boxes): registered on both the full frame and the window it would detect on one image and
    /// pixellate the other's coordinates, leaving faces uncovered in both -- fail-open. Blurring your own face
    /// cam would also defeat its point. Either flag counts, so the window hides the moment the toggle flips.
    var blurWanted: Bool { privacy?.enabled == true || blurEffectActive }

    @ScreenActor static func makeOverlay(_ mixer: MediaMixer) -> VideoTrackScreenObject {
        let o = VideoTrackScreenObject()
        o.isVisible = false
        o.videoGravity = .resizeAspectFill   // fill the rect (needed for the circle) instead of letterboxing inside it
        try? mixer.screen.addChild(o)
        return o
    }

    /// pipRect -> ScreenObject geometry: size + corner alignment + a margin inset (ScreenObject lays itself
    /// out against its parent, top-left origin, so this reproduces pipRect's rect exactly).
    @ScreenActor static func layoutOverlay(_ o: VideoTrackScreenObject, canvas: CGSize, corner: String, size: String, shape: String, track: UInt8, visible: Bool) {
        let r = pipRect(canvas: canvas, corner: corner, size: size, shape: shape)
        let m = min(canvas.width, canvas.height) * 0.04
        o.size = r.size
        o.horizontalAlignment = corner.hasSuffix("Left") ? .left : .right
        o.verticalAlignment = corner.hasPrefix("top") ? .top : .bottom
        o.layoutMargin = UIEdgeInsets(top: m, left: m, bottom: m, right: m)
        o.cornerRadius = pipCornerRadius(r, shape: shape)
        o.track = track
        o.isVisible = visible
        o.invalidateLayout()
    }

    @ScreenActor static func setPrivacyEffect(_ mixer: MediaMixer, privacy: Privacy, on: Bool) {
        if on {
            _ = mixer.screen.registerVideoEffect(privacy)
        } else {
            _ = mixer.screen.unregisterVideoEffect(privacy)
        }
    }

    /// Settings toggle. The capture-session mode (.single vs .multi) is fixed per MediaMixer instance, so
    /// turning it on/off while idle may rebuild the mixer and re-attach the current source; while a session
    /// is running the change waits for stopLive().
    func setDualCam(_ on: Bool) {
        guard dualLocked == nil else { return }
        Task {
            _ = await rebuildMixerIfNeeded()
            guard !cameraOff else { return }
            if source == "phone" { await switchTo(glasses: false) }
            else if on || dualCamActive { await switchTo(glasses: true) }   // glasses source: attach/detach the front overlay
        }
    }

    /// Swaps in a fresh MediaMixer when dual camera needs a different capture-session mode than the current
    /// one. Everything tied to the old instance (wiring, effect registration, overlay object, offscreen
    /// state) is reset so the next sync re-creates it on the new Screen. Only called while idle -- goLive()
    /// captures `mixer` for its Transcoder closure, which is only safe because this never runs mid-session.
    func rebuildMixerIfNeeded() async -> Bool {
        let multi = dualWanted && AVCaptureMultiCamSession.isMultiCamSupported
        guard multi != mixerIsMulti else { return false }
        await setOffscreenMode(false)   // stop the old render loop + unregister blur before abandoning it
        let old = mixer
        try? await old.attachVideo(nil, track: 0)
        try? await old.attachVideo(nil, track: 1)
        try? await old.attachAudio(nil)
        await old.removeOutput(sink)
        if let o = wiredUplinkOutput { await old.removeOutput(o) }
        await old.stopRunning()
        mixer = MediaMixer(captureSessionMode: multi ? .multi : .single)
        mixerIsMulti = multi
        mixerWired = false; wiredUplinkOutput = nil
        blurEffectActive = false; offscreenOn = false
        overlayObject = nil
        dualCamSwapped = false
        dualCamActive = false
        cameraDevice = nil
        cameraCapabilities = nil
        applog("stream", "mixer rebuilt, captureSessionMode=\(multi ? "multi" : "single")")
        return true
    }
}
