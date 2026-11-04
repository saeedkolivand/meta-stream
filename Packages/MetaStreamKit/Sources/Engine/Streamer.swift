// Streamer: session state + lifecycle facade. Capture, transport, bitrate, health and geometry
// live in the Streamer/ extensions; this file keeps stored state, init and stopLive.
import Camera
import CoreLogging
import Foundation
import Observation
import Combine
import AVFoundation
import CoreMedia
import Privacy
import Speech
import VideoToolbox
import UIKit
import Network
import os
import MWDATCore
import MWDATCamera
import HaishinKit
import RTMPHaishinKit
import SRTHaishinKit

public struct Mic: Identifiable, Hashable {   // id = AVAudioSessionPortDescription.uid
    public let id: String, name: String
    public init(id: String, name: String) { (self.id, self.name) = (id, name) }
}

@MainActor
@Observable
public final class Streamer {
    public var registration = "unknown"

    public var glassesState = "idle" { didSet { applog("glasses", "\(glassesState)") } }

    public var glassesOn = false

    public var rtmpState = "idle" { didSet { applog("stream", "rtmp: \(rtmpState)") } }

    public var frames = 0

    public var fps = 0

    public var kbps = 0

    public var teamID = "unknown (not sideloaded yet)"

    public var live = false { didSet { hot.live = live; SoundMix.shared.enabled = live && !muted } }

    public var liveSince: Date?

    public var connectedSince: Date?        // when the CURRENT connection went up; nil while down

    public var downtime: TimeInterval = 0   // cumulative seconds this session spent not publishing

    public var drops = 0                    // times the connection dropped this session

    public var sessionSummary: String?      // set by stopLive(), e.g. "session 42:10, 1:48 down across 3 drops"

    public var net = NetworkStats()         // NETWORK panel data, see NetworkStats.swift

    public var netPath = NetPathInfo()

    public var pathMonitor: NWPathMonitor?

    public var devices = "none seen yet"

    public var source = "phone" { didSet { syncHot(); applog("stream", "source=\(source) manual=\(manualSource)") } }   // what is going out right now

    public var manualSource = "back"       // phone camera by default; "auto" | "glasses" | "back" | "front" | "external" | "screen" (user's choice)

    /// localizedName of the connected UVC camera (iPad USB-C; iPhones never expose one), nil when none. Drives
    /// whether the source picker offers "External camera"; kept fresh by the connect/disconnect observers in init.
    public var externalCameraName: String?

    public var mics: [Mic] = []

    public var muted = false { didSet { SoundMix.shared.enabled = live && !muted } }

    public var cameraOff = false { didSet { syncHot() } }   // black frames go out instead

    // MARK: dual camera ("face cam" picture-in-picture)
    /// True while a second camera is attached on mixer track 1 and being composited as the overlay.
    public var dualCamActive = false { didSet { syncHot() } }

    /// Overlay hidden by the user (eye button) -- the camera keeps running, only the overlay object is hidden.
    public var dualCamHidden = false

    /// Phone mode only: the overlay camera is the big picture and the main camera is the small window.
    public var dualCamSwapped = false

    /// Screen.size the offscreen canvas was last sized to; ContentView hit-tests the overlay tap against it.
    public var dualCamCanvas = CGSize.zero

    public var lastPhotoAt: Date?

    public var blackTask: Task<Void, Never>?

    // MARK: health
    // ponytail: no glasses battery — MWDATCore 0.9.0 has no battery API anywhere on Device/DeviceState
    // (checked the full 0.9 type index, not just one page). Thermal is the one piece of glasses health
    // the SDK actually exposes, via DeviceState.thermalLevel — see glassesThermal below.
    public var glassesThermal: ThermalLevel? { didSet { checkGlassesThermal() } }   // nil when unknown/disconnected

    public var phoneBattery: Int? { didSet { checkPhoneBattery() } }      // nil when unknown; unmonitored outside a live session

    public var thermal: ProcessInfo.ThermalState = .nominal { didSet { checkThermal() } }

    // MARK: adaptive bitrate (active whenever phoneEncodes is true — see below)
    /// True when HaishinKit decodes+re-encodes this session. Blur can only apply to a frame we decode,
    /// so a passthrough session cannot start blurring mid-stream — the quick control says so rather than
    /// pretending the toggle worked.
    public var transcoding = false

    /// Adaptive bitrate state (Uplink/BitrateController.swift); reset on each go-live.
    public internal(set) var bitrate = BitrateController(ceilingKbps: 0, currentKbps: 0)
    /// Live value for the HUD; == the configured target while phoneEncodes is false.
    public var currentBitrateKbps: Int { bitrate.currentKbps }
    /// The user's configured bitrate; up-steps never exceed it.
    public var bitrateCeilingKbps: Int { bitrate.ceilingKbps }

    /// True whenever HaishinKit's own encoder is doing the work: h264 transcode (any source), or hevc with
    /// the phone driving video — phone-camera fallback (source == "phone") or black frames (cameraOff).
    /// False only for hevc glasses passthrough, the one case with no bitrate knob (see goLive's gate comment).
    public var phoneEncodes: Bool { hot.transcoder != nil || source == "phone" || source == "screen" || cameraOff }

    /// Short glasses state for the HUD: "streaming" | "connecting" | "off".
    public var glassesShort: String {
        let s = glassesState.lowercased()
        if s.contains("streaming") { return "streaming" }
        if ["starting", "looking", "waiting", "connecting", "session started"].contains(where: { s.contains($0) }) { return "connecting" }
        return "off"
    }

    /// The phone camera physically attached to the mixer right now -- nil whenever glasses or black frames
    /// are the source. Set after switchTo(glasses:)'s phone branch attaches (post-await, so this runs back
    /// on the main actor -- no isolation ambiguity with the attachVideo configuration closure itself), and
    /// cleared at every other mixer.attachVideo(nil) call site (switchTo's glasses branch, setCameraOff,
    /// stopLive). Live sliders patch THIS device in place via applyCameraSettings() below instead of
    /// re-attaching -- re-attaching per slider tick would visibly glitch the preview, and live, the outgoing
    /// stream, many times a second.
    public var cameraDevice: AVCaptureDevice?

    /// What the live control strip can offer for the currently attached device -- the same struct/probe
    /// SettingsView's Camera screen uses (CameraCapabilities.probe), refreshed on every attach so a
    /// front/back switch shows up immediately instead of stale-showing whatever the last camera supported.
    public var cameraCapabilities: CameraCapabilities?

    /// Mirrors fallbackPosition (private, below) for the live strip's lens filter -- setSource("front"/"back")
    /// can change the real attached position without touching @AppStorage("fallbackCamera") at all (that key
    /// is only Settings' fallback *preference*, read at evaluateSource() time), so the strip needs this
    /// rather than reading that AppStorage key directly and risking a stale/wrong lens list.
    public var cameraPosition: AVCaptureDevice.Position = .back

    public let hot = Hot()

    /// Screen share (adr/0003): decodes the broadcast extension's frames; its `sink` is the mixer while Screen is the video source.
    public let screenSource = ScreenSource()

    @ObservationIgnored public lazy var sink = LayerSink(hot: hot)

    public let faceCamFrames = TrackCounter()

    public let audioLevel = AudioLevel()   // HUD meter + dead-air state, see AudioLevel.swift

    @ObservationIgnored public lazy var recording = Recording(streamer: self)   // local recording, see Recording.swift

    @ObservationIgnored public lazy var levelTap = LevelOutput { [weak self] db in Task { @MainActor in self?.audioLevel.set(db) } }

    /// Which way up a landscape capture goes, from the phone's physical orientation -- see deviceRotated().
    public var landscapeOrientation: CaptureOrientation = .landscapeRight

    public var pip: PiPController?                        // owned here so it outlives SwiftUI view rebuilds

    // ponytail: plain optional, not weak — Speaker never references Streamer, so no retain cycle. App.swift sets it once.
    public var speaker: Speaker?

    public var privacy: Privacy?

    public var blurHidCamera = false

    public var blurEffectActive = false   // mirrors privacy.enabled -- tracks whether the effect is registered on mixer.screen

    public let lookEffect = LookEffect()
    public var lookEffectActive = false   // whether lookEffect is registered on mixer.screen, see Look.swift

    public var lastFrames = 0

    public var lastBytes = 0

    public var session: DeviceSession?

    public var camera: Camera?

    public var tokens: [any AnyListenerToken] = []        // SDK listeners die when their token is released

    public var deviceTokens: [any AnyListenerToken] = []  // per-device link/compat listeners

    public var glassesStreaming = false

    public var fallbackTask: Task<Void, Never>?
    public var gpsOnly = false                      // iPhone only sharing GPS with the iPad: no camera or mixer, see setGPSOnly

    public var fallbackPosition: AVCaptureDevice.Position = .back

    public var reconnectTask: Task<Void, Never>?   // covers first connect + every drop; cancelled by stopLive()

    public var downSince: Date?                    // set while not connected — before the first connect too

    public var escalated2m = false

    public var escalated5m = false

    public var backoff: TimeInterval = 1

    public var warnedPhoneBattery = false     // < 15%, once per session — reset in goLive()

    public var warnedThermal = false          // >= .serious, once per session — reset in goLive()

    public var warnedGlassesThermal = false   // >= .severe, once per session — reset in goLive()

    public var batteryObserver: NSObjectProtocol?

    public var thermalObserver: NSObjectProtocol?

    public var glassesThermalTask: Task<Void, Never>?

    public var phoneQuality = PhoneQuality()

    /// Geometry the current session fixed at goLive, reused as the offscreen blur canvas.
    public var sessionVideoSize = Streamer.glassesSize

    /// True from the moment goLive() fixes the geometry until stopLive(). `live` is no good here: it
    /// only flips once the first publish succeeds, long after the blur canvas needs sizing.
    public var sessionGeometryFixed = false

    /// Rebuilt per goLive() from the ingest URL's scheme.
    public var uplink = Uplink.make(for: "rtmp://")
    public var srtla: Srtla?                                  // bonding proxy, only for srtla:// ingests
    public var srtlaLinks: [Srtla.Stat] = []       // per-link state and 10 s share for the network panel

    /// A var because MediaMixer.captureSessionMode is a `let`: two cameras at once need an
    /// AVCaptureMultiCamSession (.multi), the only way to change mode is a fresh instance -- see
    /// rebuildMixerIfNeeded(). Rebuilt only while idle, so nothing live ever holds a stale instance.
    public var mixer = MediaMixer(captureSessionMode: Streamer.wantsMultiCam ? .multi : .single, multiTrackAudioMixingEnabled: true)

    public var mixerIsMulti = Streamer.wantsMultiCam

    public var mixerWired = false

    /// Dual camera as of GO LIVE (nil while idle): the session's capture mode is fixed at GO LIVE, so a
    /// Settings flip mid-stream must not change what this session does. stopLive() clears it and applies
    /// the pending change. Idle, dualWanted reads the live Settings value.
    public var dualLocked: Bool?

    public var offscreenOn = false                  // mirrors videoMixerSettings.mode == .offscreen

    public var overlayObject: VideoScreenObject?   // the face-cam window; created once per mixer

    /// The scene layer (Overlays' SceneDirector, set in App.swift): scenes, stingers, Starting/BRB/Ending roles.
    public var compositor: SceneCompositor?
    public var endingIn: Int?                // seconds left of the Ending hold, for the Go Live button

    public var makingOverlay = false                // guards the await in syncBlurEffect against the 1 s tick re-entering

    public var warnedNoMultiCam = false

    /// Whichever uplink's stream is currently registered as a mixer output, so a later goLive() can swap it
    /// out. FOUND BUG: `mixer.addOutput(uplink.output)` used to run only on the very first wireMixer() call
    /// ever (guarded by mixerWired alone) -- goLive() rebuilds `uplink` into a brand-new RTMPStream/SRTStream
    /// every session, but nothing ever added THAT one as a mixer output once mixerWired had already latched
    /// true from an earlier session (or from evaluateSource()'s auto phone-camera fallback at launch, which
    /// also calls wireMixer()). The mixer kept feeding the FIRST session's now-closed, orphaned stream while
    /// every later session connected, published, and sat there receiving zero frames of either kind -- a
    /// stream with no track at all, which is exactly "connected, publishing, channel stayed offline" with no
    /// device-report codec/track-config error to explain it. This is what actually explains that report; a
    /// shared UInt8.max videoTrackId with LayerSink (checked directly above) was considered and ruled out --
    /// HaishinKit's own dispatch is a plain array loop with no exclusivity, and its own preview views use the
    /// identical pattern deliberately.
    public var wiredUplinkOutput: (any MediaMixerOutput)?

    public init() {
        teamID = Self.readTeamID()
        applog("ui", "launch team=\(teamID)")
        liveActivity.attach(self)
        // Active playback session from launch: iOS only auto-starts PiP for an app that is "playing".
        // Playback (not record) so the orange mic indicator stays off until Go Live. Every category this app sets
        // carries .mixWithOthers: without it, launching (or going live) stops the streamer's music app.
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? s.setActive(true)
        Task { [weak self] in
            for await state in Wearables.shared.registrationStateStream() {
                self?.registration = state.description
            }
        }
        Task { [weak self] in
            for await ids in Wearables.shared.devicesStream() {
                self?.watchDevices(ids)
            }
        }
        refreshExternalCamera()
        applog("stream", "external camera at launch: \(externalCameraName ?? "none")")
        // Same observer shape as the battery/thermal ones (proven to compile here); app-lifetime, never removed.
        // didBecomeActive too: a replug while backgrounded must show up on return, not only on the next hot-plug event.
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification, UIApplication.didBecomeActiveNotification] {
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let device = (note.object as? AVCaptureDevice).map { " \($0.localizedName) (\($0.deviceType.rawValue))" }
                Task { @MainActor in
                    if let device { applog("stream", "\(name.rawValue):\(device)") }   // did iPadOS report the plug at all?
                    self?.refreshExternalCamera()
                }
            }
        }
        // Auto-rotate: only fires with rotation lock off. Same observer shape as above.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        _ = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.deviceRotated() }
        }
        startNetPathMonitor()
        gpsOnly = Self.gpsOnlyWanted(live: false)       // before evaluateSource: a GPS-only launch never opens the camera
        evaluateSource()                                // glasses off at launch → phone camera after 2 s
        Task { [weak self] in                           // 1 s stats tick for the HUD, logged every 5 s while live
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let f = self.hot.frames, b = self.hot.bytes
                self.fps = f - self.lastFrames
                self.kbps = (b - self.lastBytes) * 8 / 1000
                self.frames = f
                self.lastFrames = f; self.lastBytes = b
                tick += 1
                // Sample BEFORE adaptBitrate(): it consumes (resets) hot.congested.
                self.recordNetSample(congested: self.hot.congested)
                await self.adaptBitrate()
                self.srtla?.setCut(self.currentBitrateKbps > 0 && self.currentBitrateKbps * 10 < self.bitrateCeilingKbps * 7)
                if !self.gpsOnly { await self.syncBlurEffect() }   // it would restart the offscreen render loop for the overlays
                self.checkBlurStall()
                self.checkDeadAir()
                self.compositor?.checkBRB()
                self.onSecond(self)
                self.recording.checkSource()
                self.liveActivity.sync(self)
                if self.live, tick % 5 == 0 {
                    let mode = self.hot.transcoder == nil ? "hevc-passthrough" : "h264-transcode"
                    applog("stream", "stats source=\(self.source) \(mode) glassesFps=\(self.fps) glassesKbps=\(self.kbps) sent=\(self.hot.sent) decoded=\(self.hot.transcoder?.decoded ?? 0) appended=\(self.hot.appended) mixerOut=\(self.hot.mixerOut)")
                }
            }
        }
    }

    public var rotateTask: Task<Void, Never>?
    public let liveActivity = LiveActivityController()   // Lock Screen / Dynamic Island card, see LiveActivity.swift
    /// Session events for the features the engine doesn't know (app bot, Telegram live post, session log); App.swift
    /// sets them (Android: Session.live). onSecond runs on the stats tick, live or not.
    public var onSessionStarted: (Streamer) -> Void = { _ in }
    public var onSecond: (Streamer) -> Void = { _ in }
    public var onSessionEnded: () -> Void = {}

    public func stopLive() {
        if live { onSessionEnded() }
        reconnectTask?.cancel()
        reconnectTask = nil
        srtla?.stop(); srtla = nil; srtlaLinks = []
        sessionGeometryFixed = false   // idle previews size from the phone camera again, not the ended session
        if let since = downSince, live { downtime += Date().timeIntervalSince(since) }
        downSince = nil
        speaker?.stopRepeating(id: "rtmp")
        stopDeadAir(recovered: false)
        if let start = liveSince {
            let summary = "session \(Self.fmtClock(Date().timeIntervalSince(start))), \(Self.fmtClock(downtime)) down across \(drops) drops"
            sessionSummary = summary
            applog("stream", summary)
        }
        live = false
        pip?.setArmed(false)   // idle: backgrounding may suspend the app again
        liveActivity.end()
        liveSince = nil
        connectedSince = nil
        hot.warm = false
        hot.transcoder?.invalidate()
        hot.transcoder = nil
        syncHot()   // decode stopped: glasses preview (if that's what routed it) falls back to the raw HEVC feed
        bitrate = BitrateController(ceilingKbps: bitrate.ceilingKbps, currentKbps: 0)
        fallbackTask?.cancel()
        blackTask?.cancel(); blackTask = nil
        stopHealthMonitoring()
        rtmpState = "stopped"
        cameraDevice = nil
        cameraCapabilities = nil
        dualLocked = nil   // idle again: Settings' dualCam value is live, and any change made mid-stream is applied below
        Task {
            // Force blur off unconditionally, even if the toggle is still on: a session that ends with it
            // on must not leave the offscreen render loop running into the next goLive() (see
            // setScreenSize's doc -- that loop is the one thing reading Screen.size, and the next session
            // resizes it). goLive() also forces this defensively, so this isn't the only thing standing
            // between the two sessions, but it stops the loop from spinning uselessly while idle either way.
            await setOffscreenMode(false)
            try? await mixer.attachVideo(nil)
            await detachOverlay()
            await uplink.close()
            if dualLocked == nil { _ = await rebuildMixerIfNeeded() }   // a dual-camera toggle flipped mid-stream takes effect now (skipped if GO LIVE was already pressed again)
        }
        compositor?.sessionEnded()   // a Starting countdown or BRB still running: back to the scene before it
        source = "glasses"
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])   // mic off; the playback session stays so the next goLive can arm PiP
    }

    /// "m:ss" for the session summary, e.g. 1:48. Minutes aren't padded/capped — a long stream just reads "72:03".
    public static func fmtClock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // Free Apple IDs get a "personal team"; its ID is only visible inside the signed app's provisioning profile.
    public static func readTeamID() -> String {
        let fallback = "unknown (not sideloaded yet)"
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let regex = try? NSRegularExpression(pattern: #"<key>TeamIdentifier</key>\s*<array>\s*<string>([A-Z0-9]+)</string>"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return fallback }
        return String(text[range])
    }
}

