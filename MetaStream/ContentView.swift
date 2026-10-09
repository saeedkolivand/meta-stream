import SwiftUI
import MWDATCore
import AVFoundation
import CoreMotion

// MARK: - UIKit bridges

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
}

struct PreviewView: UIViewRepresentable {
    @EnvironmentObject var streamer: Streamer
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.displayLayer.videoGravity = .resizeAspect
        streamer.preview = view.displayLayer
        if streamer.pip == nil { streamer.pip = PiPController(layer: view.displayLayer) }
        return view
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

/// Viewfinder-only level: CMMotionManager roll -> a horizon line ContentView draws over the preview.
/// Started/stopped with the Settings toggle so it costs nothing when off; never touches the capture
/// pipeline or encoded video (see gridOverlay/levelOverlay in ContentView -- purely a SwiftUI overlay).
/// ponytail: no background-state teardown -- ContentView is the app's root screen and never truly
/// disappears in normal use, so there's no onDisappear to hook; if that stops holding (e.g. a future
/// full-screen cover over it), stop() it there too.
private final class LevelMonitor: ObservableObject {
    @Published var rollDegrees: Double = 0
    private let mm = CMMotionManager()
    func start() {
        guard mm.isDeviceMotionAvailable, !mm.isDeviceMotionActive else { return }
        mm.deviceMotionUpdateInterval = 1.0 / 20   // smooth enough for a horizon line, cheap enough to leave running
        mm.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            self?.rollDegrees = data.attitude.roll * 180 / .pi
        }
    }
    func stop() { mm.stopDeviceMotionUpdates() }
}

// MARK: - Live screen

struct ContentView: View {
    @EnvironmentObject var streamer: Streamer
    @EnvironmentObject var speaker: Speaker
    @EnvironmentObject var chat: ChatFeed
    @EnvironmentObject var platforms: Platforms
    @EnvironmentObject var privacy: Privacy
    @AppStorage("rtmpURL") var ingestURL = "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/"
    // ponytail: stream key in UserDefaults; move to Keychain if the phone is shared.
    @AppStorage("streamKey") var streamKey = ""
    // Repurposed from "which platform's webview to show" (Phase 1a) to "which platform an outgoing chat
    // message targets" now that the sheet shows one aggregated native list instead of a per-site webview.
    @AppStorage("chatSite") var chatSite = "kick"
    // Which origins get read aloud AND shown in the chat list - the list is ChatFeed.recent verbatim,
    // so a voice toggle being off means that platform's messages never arrive here either.
    @AppStorage("voiceKick") var voiceKick = true
    @AppStorage("voiceTwitch") var voiceTwitch = true
    @AppStorage("voiceYouTube") var voiceYouTube = true
    @AppStorage("dualCam") var dualCamOn = false
    @AppStorage("dualCamCorner") var dualCamCorner = "topRight"
    @AppStorage("dualCamSize") var dualCamSize = "m"
    @AppStorage("dualCamShape") var dualCamShape = "rounded"
    @AppStorage("blurOn") var blurOn = false
    @AppStorage("blurFaces") var blurFaces = true
    @AppStorage("blurText") var blurText = true
    @AppStorage("blurBarcodes") var blurBarcodes = true
    @AppStorage("chatChannel") var chatChannel = ""
    @AppStorage("resolution") var resolution = "high"
    @AppStorage("fps") var fpsSetting = 30
    @AppStorage("micUID") var micUID = ""
    @AppStorage("fallbackCamera") var fallbackCamera = "back"
    @AppStorage("keepAwake") var keepAwake = true
    @AppStorage("bitrateKbps") var bitrateKbps = 4000
    @AppStorage("srtLatencyMs") var srtLatencyMs = 2000
    @AppStorage("phoneHeight") var phoneHeight = 720
    @AppStorage("phoneLandscape") var phoneLandscape = false
    /// Index into chatSizes. Defaults one step above system size: chat is read at a glance from a phone
    /// mounted on a dash, not held at reading distance.
    @AppStorage("chatTextSize") var chatTextSize = 1
    private static let chatSizes: [DynamicTypeSize] = [.large, .xxLarge, .accessibility2, .accessibility4]
    @AppStorage("phoneFps") var phoneFps = 30
    @AppStorage("phoneStabilization") var phoneStabilization = "off"
    @AppStorage("codec") var codecPref = "auto"
    @AppStorage("platform") var platformPref = "kick"

    // Live camera controls -- same keys SettingsView's Camera screen writes, so the two views never
    // disagree about the current value (see CameraSettings.loadFromDefaults()).
    @AppStorage("camLens") var camLens = "wide"
    @AppStorage("camZoom") var camZoom = 1.0
    @AppStorage("camExposureManual") var camExposureManual = false
    @AppStorage("camExposureBiasEV") var camExposureBiasEV = 0.0
    @AppStorage("camTorchLevel") var camTorchLevel = 0.0
    @AppStorage("camWhiteBalanceManual") var camWhiteBalanceManual = false
    @AppStorage("camMirrored") var camMirrored = false
    @AppStorage("camGridOn") var camGridOn = false
    @AppStorage("camLevelOn") var camLevelOn = false
    @AppStorage(LiveCameraControl.storageKey) var liveControlOrderRaw = LiveCameraControl.defaultOrderRaw
    /// auto: only YouTube (enhanced RTMP) and custom servers take the glasses' HEVC untouched. Kick, Restream,
    /// Instagram and TikTok are H.264-only ingests, and Twitch gates HEVC behind Affiliate, so they get a transcode.
    private var codec: String {
        // adr/0001: blur has to decode every frame to obscure it, so it forces a transcode and
        // outranks even an explicit HEVC choice — you cannot blur a frame you never decode.
        // Dual camera is the same story: the face-cam overlay (and glasses video, which only reaches the mixer
        // as decoded frames) is composited on the phone, so it re-encodes whatever codec was picked.
        // Precedence: blur / dual camera > explicit codec > protocol capability > destination table.
        if blurOn || dualCamOn { return "h264" }
        guard codecPref == "auto" else { return codecPref }
        // SRT carries whatever the server decodes, and passthrough is the entire reason to use it:
        // no transcode means no PiP window needed to keep streaming in the background.
        if ingestURL.lowercased().hasPrefix("srt://") { return "hevc" }
        return ["youtube", "custom"].contains(platformPref) ? "hevc" : "h264"
    }

    @State private var showSettings = false
    @State private var showChat = false
    @State private var showStatus = false
    @State private var showManager = false
    @State private var showCameraControls = false
    @State private var photoFlash = false
    @StateObject private var emotes = Emotes()
    @StateObject private var levelMonitor = LevelMonitor()
    @State private var chatText = ""
    @State private var atBottom = true   // tracks whether the chat list should auto-scroll on new messages
    @State private var focusTap: CGPoint?   // raw view coords of the last tap-to-focus, for the square indicator
    @State private var aeafLocked = false   // AE/AF lock badge -- see Streamer.setAEAFLocked
    @State private var pinchStartZoom: Double?   // camZoom at the start of the current pinch -- see the MagnifyGesture below

    /// Data-driven strip contents: see LiveCameraControl's doc. Falls back to the full default set if the
    /// stored value is empty or unparseable, so there's never a dead strip with nothing shown.
    private var liveControlOrder: [LiveCameraControl] { LiveCameraControl.order(from: liveControlOrderRaw) }

    /// True once at least one origin is set up to produce chat - Kick needs only a channel name, Twitch/
    /// YouTube need a connected account. Drives the sheet's "no chat source" empty state.
    private var chatConfigured: Bool {
        !chatChannel.isEmpty || platforms.twitchConnected || platforms.ytConnected
    }

    /// Platforms an outgoing message can actually go to right now - the segmented picker in the compose
    /// bar only ever shows these, and `sendChat()` falls back to the first one if `chatSite` points at a
    /// platform that isn't configured/connected.
    private var sendTargets: [String] {
        var targets: [String] = []
        if !chatChannel.isEmpty { targets.append("kick") }
        if platforms.twitchConnected { targets.append("twitch") }
        if platforms.ytConnected { targets.append("youtube") }
        return targets
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                ZStack {
                    // Tap-to-focus/expose and long-press AE/AF lock, phone source only -- see
                    // Streamer.tapToFocus's and Streamer.setAEAFLocked's docs. Gestures, not strip controls
                    // (per CameraSettings.LiveCameraControl's doc), so they work whether or not the strip
                    // below is open. Long-press and tap share one touch, so they're combined exclusively
                    // (long-press wins if it completes, tap fires otherwise) rather than as two independent
                    // gestures racing on the same finger.
                    PreviewView().ignoresSafeArea()      // one layer for glasses, phone camera and black frames; PiP uses it too
                        .contentShape(Rectangle())
                        .gesture(
                            LongPressGesture(minimumDuration: 0.5).exclusively(before: SpatialTapGesture())
                                .onEnded { value in
                                    guard phoneCamControllable else { return }
                                    switch value {
                                    case .first:
                                        tap(strong: true)
                                        aeafLocked.toggle()
                                        streamer.setAEAFLocked(aeafLocked)
                                    case .second(let tapValue):
                                        // A tap on the face-cam window swaps which camera is big; anywhere else
                                        // falls through to tap-to-focus (skipped while swapped: cameraDevice is
                                        // the back camera, which is now the small window).
                                        let canvas = streamer.dualCamCanvas
                                        if streamer.dualCamActive, !streamer.dualCamHidden,
                                           let cp = Streamer.canvasPoint(forViewPoint: tapValue.location, viewSize: geo.size, canvas: canvas),
                                           Streamer.pipRect(canvas: canvas, corner: dualCamCorner, size: dualCamSize, shape: dualCamShape).contains(cp) {
                                            tap()
                                            streamer.swapDualCam()
                                            return
                                        }
                                        if streamer.dualCamSwapped { return }
                                        tap()
                                        focusTap = tapValue.location
                                        let norm = CGPoint(x: tapValue.location.x / max(geo.size.width, 1), y: tapValue.location.y / max(geo.size.height, 1))
                                        let orientation: AVCaptureVideoOrientation = phoneLandscape ? streamer.landscapeOrientation : .portrait
                                        streamer.tapToFocus(at: CameraSettings.devicePoint(forViewPoint: norm, orientation: orientation, mirrored: camMirrored))
                                        Task { try? await Task.sleep(for: .milliseconds(700)); withAnimation { focusTap = nil } }
                                    }
                                }
                        )
                        // Two-finger pinch, independent of the one-finger gesture above -- simultaneousGesture
                        // so neither cancels the other. Multiplies from the zoom value AT PINCH START (not
                        // absolute -- MagnifyGesture.magnification is already relative to gesture start, so
                        // capturing camZoom once and multiplying every update is correct, no running delta
                        // needed), through the exact CameraSettings.clamped() the zoom slider and
                        // CameraSettings.apply use -- one zoom value, three ways to change it, same clamp.
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    guard phoneCamControllable, !streamer.dualCamSwapped else { return }   // swapped: cameraDevice is the small window
                                    if pinchStartZoom == nil { pinchStartZoom = camZoom }
                                    let range = streamer.cameraCapabilities?.zoomRange ?? (camZoom...camZoom)
                                    camZoom = CameraSettings.clamped((pinchStartZoom ?? camZoom) * Double(value.magnification), min: range.lowerBound, max: range.upperBound)
                                    streamer.applyCameraSettings()
                                }
                                .onEnded { _ in pinchStartZoom = nil }
                        )

                    if camGridOn { gridOverlay(size: geo.size) }
                    if camLevelOn { levelOverlay(size: geo.size) }
                }
            }
            .ignoresSafeArea()

            if let p = focusTap {
                RoundedRectangle(cornerRadius: 4).stroke(Color.yellow, lineWidth: 1.5)
                    .frame(width: 70, height: 70)
                    .position(p)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if aeafLocked {
                VStack {
                    Text("AE/AF LOCK")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.top, 54)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if streamer.cameraOff {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash.fill").font(.system(size: 44))
                    Text("Camera off").font(.headline)
                    Text("viewers see black").font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }

            VStack {
                hud
                Spacer()
                quickControls
                controls
            }
            .padding(.horizontal)

            if Streamer.glassesConfigured, streamer.registration != "registered" { registerCard }

            if photoFlash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            // Trailing edge, vertically centered: stays clear of the HUD row (top), GO LIVE and the rest of
            // `controls` (bottom), and the preview centre, while staying thumb-reachable one-handed. Only
            // meaningful with the phone camera live -- the glasses expose none of this.
            if showCameraControls, phoneCamControllable {
                HStack {
                    Spacer()
                    cameraControlStrip.padding(.trailing, 10)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showManager) { StreamManagerView() }
        .sheet(isPresented: $showChat) {
            chatSheet
                .presentationDetents([.fraction(0.45), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
                .presentationDragIndicator(.visible)
                .presentationBackground(.black)
        }
        .alert("Status", isPresented: $showStatus) { Button("OK") {} } message: {
            Text("Meta: \(streamer.registration)\nGlasses: \(streamer.glassesState)\nDevices: \(streamer.devices)\nRTMP: \(streamer.rtmpState)\nDrops: \(streamer.drops)\nFrames: \(streamer.frames)\nTeam ID: \(streamer.teamID)" + (streamer.sessionSummary.map { "\nLast: \($0)" } ?? ""))
        }
        .task {
            // ponytail: one consumer for the app's lifetime. ChatFeed buffers, Speaker bounds its own lanes,
            // so nothing here needs backpressure handling.
            for await e in chat.events { speaker.speak(e) }
        }
        .onAppear { startChat(); applyBlur(); if camLevelOn { levelMonitor.start() } }
        .onChange(of: blurOn) { _, _ in applyBlur() }
        .onChange(of: blurFaces) { _, _ in applyBlur() }
        .onChange(of: blurText) { _, _ in applyBlur() }
        .onChange(of: blurBarcodes) { _, _ in applyBlur() }
        .onChange(of: chatChannel) { _, _ in startChat() }
        .onChange(of: voiceKick) { _, _ in startChat() }
        .onChange(of: voiceTwitch) { _, _ in startChat() }
        .onChange(of: voiceYouTube) { _, _ in startChat() }
        .onChange(of: platforms.twitchConnected) { _, _ in startChat() }
        .onChange(of: platforms.ytConnected) { _, _ in startChat() }
        // Glasses (re)connecting can flip the source out from under an open strip -- nothing left to control.
        // aeafLocked resets too: a lock only ever made sense against the phone device it was set on.
        .onChange(of: streamer.source) { _, s in if s != "phone" { showCameraControls = false; aeafLocked = false } }
        .onChange(of: streamer.manualSource) { _, s in if s == "external" { showCameraControls = false; aeafLocked = false } }
        .onChange(of: camLevelOn) { _, on in on ? levelMonitor.start() : levelMonitor.stop() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onChange(of: keepAwake) { _, v in UIApplication.shared.isIdleTimerDisabled = v }
        .onChange(of: streamer.lastPhotoAt) { _, _ in
            withAnimation(.easeOut(duration: 0.1)) { photoFlash = true }
            Task { try? await Task.sleep(for: .milliseconds(120)); withAnimation(.easeIn(duration: 0.3)) { photoFlash = false } }
        }
    }

    // MARK: HUD

    private var hud: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if Streamer.glassesConfigured {
                    Button { showStatus = true } label: {
                        pill("eyeglasses", streamer.glassesShort, glassesColor)
                    }
                    .buttonStyle(.plain)
                }

                if streamer.live {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        // Amber while down: the timer measures the session, never the connection, so it
                        // has to show degraded time rather than quietly counting dead air as healthy.
                        let down = streamer.connectedSince == nil
                        pill(down ? "exclamationmark.triangle.fill" : "record.circle.fill",
                             down ? "down " + elapsed(ctx.date) : elapsed(ctx.date),
                             down ? .orange : .red)
                    }
                    pill("waveform", "\(streamer.fps) fps · \(streamer.kbps) kbps", .white)
                    if streamer.currentBitrateKbps > 0, streamer.currentBitrateKbps < bitrateKbps {
                        pill("arrow.down.right.circle", "\(streamer.currentBitrateKbps)k cap", .orange)
                    }
                } else {
                    pill("antenna.radiowaves.left.and.right", streamer.rtmpState, .gray)
                }
                if let pb = streamer.phoneBattery, pb < 30 {
                    pill("battery.25", "phone \(pb)%", pb < 15 ? .orange : .white)
                }
                if let gt = streamer.glassesThermal, let heat = glassesHeat(gt) {
                    pill("thermometer", "glasses \(heat)", heat == "warm" ? .white : .orange)
                }
                if blurOn {
                    pill(privacy.stalled ? "eye.trianglebadge.exclamationmark" : "eye.slash.fill",
                         privacy.stalled ? "blur failed" : "blur", privacy.stalled ? .orange : .white)
                }
                if streamer.thermal != .nominal {
                    pill("thermometer", thermalLabel, streamer.thermal == .fair ? .white : .orange)
                }
                pill(streamer.source == "phone" ? (streamer.manualSource == "external" ? "video.fill" : "iphone") : "eyeglasses",
                     streamer.manualSource == "auto" ? "auto · \(streamer.source)"
                         : streamer.manualSource == "external" ? (streamer.externalCameraName ?? "external") : streamer.manualSource,
                     streamer.source == "phone" ? .orange : .white)
                Button { tap(); speaker.muted.toggle() } label: {
                    // Silences chat and alerts only. Stream warnings speak regardless — see Speaker.
                    pill(speaker.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", speaker.muted ? "tts off" : "tts", speaker.muted ? .orange : .white)
                }
                .buttonStyle(.plain)
                Button { tap(); streamer.capturePhoto() } label: {
                    pill("camera.shutter.button", "photo", .white)
                }
                .buttonStyle(.plain)
                .disabled(streamer.glassesShort != "streaming")
                .opacity(streamer.glassesShort == "streaming" ? 1 : 0.4)
                Button { tap(); showManager = true } label: {
                    pill("slider.horizontal.3", "manage", .cyan)
                }
                .buttonStyle(.plain)
                if phoneCamControllable {
                    Button { tap(); showCameraControls.toggle() } label: {
                        pill("camera.aperture", "cam", showCameraControls ? .cyan : .white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    /// Privacy exposes plain vars, not @Published — a published hot path would cost a MainActor hop on
    /// every decoded frame. So settings are written through here instead of bound.
    private func applyBlur() {
        privacy.enabled = blurOn
        privacy.options = .init(faces: blurFaces, text: blurText, barcodes: blurBarcodes)
        streamer.applyDualCamLayout()   // face-cam window hides the moment blur turns on -- see Streamer.blurWanted
    }

    /// Starts every enabled origin that has what it needs. Kick needs only a slug; Twitch and YouTube
    /// need a connected account. Each origin is owned by exactly one feed, so nothing arrives twice.
    private func startChat() {
        var origins = 0
        if voiceKick, !chatChannel.isEmpty { chat.start(kickSlug: chatChannel); origins += 1 } else { chat.stopKick() }
        if voiceTwitch, platforms.twitchConnected { chat.startTwitch(platforms: platforms); origins += 1 } else { chat.stopTwitch() }
        if voiceYouTube, platforms.ytConnected { chat.startYouTube(platforms: platforms); origins += 1 } else { chat.stopYouTube() }
        // Only prefix "on Kick, …" when more than one origin is live — otherwise it's noise on every line.
        speaker.showOrigin = origins > 1
        Task { await emotes.load(twitchID: platforms.twitchConnected ? platforms.twitchUserID : nil) }
    }

    /// Phone-camera controls (tap-to-focus, pinch zoom, lens strip) only drive a built-in camera; a UVC
    /// external camera exposes none of them, so they're hidden/no-op'd for it.
    private var phoneCamControllable: Bool { streamer.source == "phone" && streamer.manualSource != "external" }

    /// Shows what is actually on air, not what was asked for — on auto those differ whenever the
    /// glasses drop and the phone takes over.
    private var sourceIcon: String {
        switch streamer.manualSource {
        case "glasses": return "eyeglasses"
        case "back": return "camera.fill"
        case "front": return "camera.rotate.fill"
        case "external": return "video.fill"
        default: return streamer.source == "phone" ? "iphone" : "eyeglasses"
        }
    }

    /// nil below moderate — a pill that never clears is noise on a screen you glance at mid-walk.
    private func glassesHeat(_ level: ThermalLevel) -> String? {
        switch level {
        case .moderate: return "warm"
        case .severe: return "hot"
        case .critical, .emergency, .shutdown: return "overheating"
        default: return nil
        }
    }

    private var thermalLabel: String {
        switch streamer.thermal {
        case .fair: return "warm"
        case .serious: return "hot"
        case .critical: return "overheating"
        default: return "ok"
        }
    }

    private var glassesColor: Color {
        switch streamer.glassesShort {
        case "streaming": return .green
        case "connecting": return .orange
        default: return .gray
        }
    }

    private func elapsed(_ now: Date) -> String {
        guard let since = streamer.liveSince else { return "00:00" }
        let s = Int(now.timeIntervalSince(since))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func pill(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: Controls

    private var controls: some View {
        HStack(alignment: .center, spacing: streamer.dualCamActive ? 8 : 18) {   // one extra button below: tighter so the row still fits
            if Streamer.glassesConfigured {
                roundButton(streamer.glassesOn ? "eyeglasses" : "eyeglasses.slash", filled: streamer.glassesOn) {
                    tap()
                    streamer.glassesOn ? streamer.stopGlasses() : streamer.startGlasses(resolution: resolution, fps: UInt(fpsSetting))
                }
            }
            // A picker, not a cycler: hunting for the right source by tapping through four states is
            // the wrong interaction when the shot is already wrong on stream.
            Menu {
                Picker("Video source", selection: Binding(get: { streamer.manualSource },
                                                          set: { tap(); streamer.setSource($0) })) {
                    Label("Auto", systemImage: "wand.and.stars").tag("auto")
                    if Streamer.glassesConfigured {
                        Label("Glasses", systemImage: "eyeglasses").tag("glasses")
                    }
                    Label("Back camera", systemImage: "camera.fill").tag("back")
                    Label("Front camera", systemImage: "camera.rotate.fill").tag("front")
                    if streamer.externalCameraName != nil {   // iPad USB-C UVC camera, only while plugged in
                        Label("External camera", systemImage: "video.fill").tag("external")
                    }
                }
            } label: {
                Image(systemName: sourceIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(streamer.manualSource == "auto" ? .white : .black)
                    .frame(width: 52, height: 52)
                    .background(streamer.manualSource == "auto" ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.white), in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                tap(strong: true)
                if streamer.live {
                    streamer.stopLive()
                } else {
                    streamer.goLive(url: ingestURL, key: streamKey, micUID: micUID,
                                    fallbackPosition: fallbackCamera == "front" ? .front : .back,
                                    bitrateKbps: bitrateKbps, codec: codec, srtLatencyMs: srtLatencyMs,
                                    quality: .init(height: phoneHeight, landscape: phoneLandscape, fps: phoneFps,
                                                   stabilization: phoneStabilization))
                }
            } label: {
                ZStack {
                    Circle().fill(streamer.live ? Color.red : Color.green)
                        .frame(width: 84, height: 84)
                        .shadow(color: (streamer.live ? Color.red : Color.green).opacity(0.5), radius: 12)
                    Text(streamer.live ? "END" : "GO\nLIVE")
                        .font(.system(size: 15, weight: .heavy)).multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(duration: 0.3), value: streamer.live)

            // Hide/show the face-cam window mid-stream (the second camera keeps running; only the overlay goes).
            if streamer.dualCamActive {
                roundButton(streamer.dualCamHidden ? "eye.slash" : "eye", filled: streamer.dualCamHidden) {
                    tap()
                    streamer.setDualCamHidden(!streamer.dualCamHidden)
                }
            }
            roundButton("bubble.left.and.bubble.right.fill", filled: showChat) { tap(); showChat.toggle() }
            roundButton("gearshape.fill", filled: false) { tap(); showSettings = true }
        }
        .padding(.bottom, 12)
    }

    /// Mic, camera and privacy, fixed and always on screen. These are the controls you need in the second
    /// something goes wrong, so they must never live in the scrolling status strip where a long run of
    /// pills can push them off the edge — you cannot scroll a pill row one-handed while walking.
    private var quickControls: some View {
        HStack(spacing: 12) {
            quickButton(streamer.muted ? "mic.slash.fill" : "mic.fill",
                        streamer.muted ? "Muted" : "Mic",
                        style: streamer.muted ? .stopped : .live) {
                streamer.setMuted(!streamer.muted)
            }

            quickButton(streamer.cameraOff ? "video.slash.fill" : "video.fill",
                        streamer.cameraOff ? "Hidden" : "Camera",
                        style: streamer.cameraOff ? .stopped : .live) {
                streamer.setCameraOff(!streamer.cameraOff)
            }

            quickButton(blurOn ? "eye.slash.fill" : "eye.fill",
                        blurOn ? (streamer.live && !streamer.transcoding ? "Next stream" : "Blur on") : "Blur off",
                        style: !blurOn ? .off : (streamer.live && !streamer.transcoding ? .pending : .protecting)) {
                blurOn.toggle()
            }
        }
        .padding(.bottom, 10)
    }

    /// One colour per meaning, never two shades of the same thing: green is going out, red is not going
    /// out, blue is actively protecting, amber is asked for but not in effect, grey is off. A toggle you
    /// have to squint at is useless at the moment you need it.
    private enum QuickStyle {
        case live, stopped, protecting, pending, off
        var tint: Color? {
            switch self {
            case .live: return .green
            case .stopped: return .red
            case .protecting: return .blue
            case .pending: return .orange
            case .off: return nil
            }
        }
    }

    private func quickButton(_ icon: String, _ label: String, style: QuickStyle,
                             action: @escaping () -> Void) -> some View {
        Button {
            tap(strong: true)
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(label).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(style.tint.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(.ultraThinMaterial))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(style.tint == nil ? 0.25 : 0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func roundButton(_ icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(filled ? .black : .white)
                .frame(width: 52, height: 52)
                .background(filled ? AnyShapeStyle(.white) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Live camera control strip -- "set before you walk" controls live in SettingsView's Camera
    // screen (ISO, shutter, HDR, distortion correction: deliberate, set-once). These are the ones worth
    // changing mid-stream, applied straight to the live device -- see Streamer.applyCameraSettings.

    private var cameraControlStrip: some View {
        // Landscape is too short for every row: scroll only when it doesn't fit.
        ViewThatFits(in: .vertical) {
            controlRows
            ScrollView(showsIndicators: false) { controlRows }
        }
        .padding(12)
        .frame(width: 156)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var controlRows: some View {
        VStack(spacing: 14) {
            ForEach(liveControlOrder, id: \.self) { liveControlRow($0) }
        }
    }

    @ViewBuilder
    private func liveControlRow(_ control: LiveCameraControl) -> some View {
        let cap = streamer.cameraCapabilities
        switch control {
        case .lens:
            // Ascending by real zoom factor and labeled with THIS device's actual multipliers -- see
            // CameraSettings.lensOptions (fixes the device-confirmed bug where this used to render "1,
            // 0.5, 2" from CameraLens's declaration order with a hardcoded telephoto "2"). Empty when this
            // position has only one lens. streamer.cameraPosition, not the fallbackCamera AppStorage
            // preference -- setSource("front"/"back") can diverge from it, see that property's old doc.
            let options = CameraSettings.lensOptions(position: streamer.cameraPosition)
            if !options.isEmpty {
                HStack(spacing: 6) {
                    ForEach(options, id: \.lens.rawValue) { option in
                        Button {
                            tap()
                            camLens = option.lens.rawValue
                            camZoom = option.zoomFactor   // one zoom value, three ways to change it -- see the pinch gesture's doc
                            // No reattach: captureDevice(position:) already attaches the virtual device
                            // whose videoZoomFactor domain option.zoomFactor is IN (see CameraSettings.
                            // captureDevice's doc -- fixes the ~6x-on-telephoto bug), so this is a live
                            // setting change like any other slider, not a different device.
                            applog("stream", "camera lens=\(option.lens.rawValue) zoom=\(String(format: "%.2f", option.zoomFactor))x")
                            streamer.applyCameraSettings()
                        } label: {
                            Text(option.label)
                                .font(.caption2.weight(.bold))
                                .frame(width: 30, height: 30)
                                .foregroundStyle(camLens == option.lens.rawValue ? .black : .white)
                                .background(camLens == option.lens.rawValue ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.15)), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .zoom:
            if let range = cap?.zoomRange, range.upperBound > range.lowerBound {
                liveSlider("magnifyingglass", String(format: "%.1fx", camZoom), $camZoom, range)
            }
        case .exposure:
            if let range = cap?.exposureBiasRange {
                VStack(alignment: .leading, spacing: 2) {
                    liveSlider("sun.max", String(format: "%.1f EV", camExposureBiasEV), $camExposureBiasEV, range, disabled: camExposureManual)
                    // Bias only affects auto exposure -- custom ISO/shutter ignores it (see CameraSettings'
                    // type doc). Disabled rather than force-flipping the user's Settings choice.
                    if camExposureManual {
                        Text("manual exposure on").font(.system(size: 9)).foregroundStyle(.orange)
                    }
                }
            }
        case .torch:
            if cap?.torch == true {
                liveSlider("flashlight.on.fill", camTorchLevel <= 0 ? "off" : String(format: "%.0f%%", camTorchLevel * 100), $camTorchLevel, 0...1)
            }
        case .whiteBalanceLock:
            if cap?.whiteBalanceManual == true {
                Button {
                    tap()
                    camWhiteBalanceManual.toggle()
                    streamer.setWhiteBalanceLocked(camWhiteBalanceManual)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: camWhiteBalanceManual ? "lock.fill" : "lock.open")
                        Text(camWhiteBalanceManual ? "WB locked" : "Lock WB").font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(camWhiteBalanceManual ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(.white.opacity(0.15)), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        case .stabilization:
            // Deliberate discrete Menu, not a slider you graze -- each mode crops differently (visible
            // framing jump) and the stronger modes add latency, so switching has to be a deliberate tap.
            // Writes through phoneStabilization, the same @AppStorage key Settings' Camera screen uses.
            Menu {
                Picker("Stabilisation", selection: Binding(
                    get: { phoneStabilization },
                    set: { newValue in tap(); phoneStabilization = newValue; streamer.setStabilization(newValue) })) {
                    Text("Off").tag("off")
                    Text("Standard").tag("standard")
                    Text("Cinematic").tag("cinematic")
                    Text("Action").tag("action")
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "gyroscope")
                    Text(stabilizationShort(phoneStabilization)).font(.caption2)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(phoneStabilization == "off" ? AnyShapeStyle(.white.opacity(0.15)) : AnyShapeStyle(Color.blue.gradient), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        case .mirror:
            // Mirroring was Settings-only; exposed live here too, same camMirrored key -- see
            // Streamer.setMirrored's doc for why this is a reattach, not a live connection tweak.
            Button {
                tap()
                camMirrored.toggle()
                streamer.setMirrored(camMirrored)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.left.and.right")
                    Text(camMirrored ? "Mirrored" : "Mirror").font(.caption2)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(camMirrored ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(.white.opacity(0.15)), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private func stabilizationShort(_ mode: String) -> String {
        switch mode {
        case "standard": return "STD"
        case "cinematic": return "CINE"
        case "action": return "ACTION"
        default: return "OFF"
        }
    }

    /// Rule-of-thirds grid, viewfinder only -- never touches the encoded video (see camGridOn's Settings footer).
    private func gridOverlay(size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: size.width / 3, y: 0)); p.addLine(to: CGPoint(x: size.width / 3, y: size.height))
            p.move(to: CGPoint(x: size.width * 2 / 3, y: 0)); p.addLine(to: CGPoint(x: size.width * 2 / 3, y: size.height))
            p.move(to: CGPoint(x: 0, y: size.height / 3)); p.addLine(to: CGPoint(x: size.width, y: size.height / 3))
            p.move(to: CGPoint(x: 0, y: size.height * 2 / 3)); p.addLine(to: CGPoint(x: size.width, y: size.height * 2 / 3))
        }
        .stroke(Color.white.opacity(0.5), lineWidth: 0.75)
        .allowsHitTesting(false)
    }

    /// Horizon level from LevelMonitor's roll, viewfinder only -- same encode-never-sees-it guarantee as
    /// the grid. Turns green within ~1.5° of level, matching the Camera app's own level convention.
    private func levelOverlay(size: CGSize) -> some View {
        let roll = levelMonitor.rollDegrees
        let level = abs(roll) < 1.5
        return Rectangle()
            .fill(level ? Color.green : Color.white)
            .frame(width: size.width * 0.6, height: 1.5)
            .rotationEffect(.degrees(-roll))
            .position(x: size.width / 2, y: size.height / 2)
            .allowsHitTesting(false)
    }

    /// Fires on every value change, not just release -- SwiftUI's Slider already updates a plain
    /// Binding<Double> continuously while dragging, so this is what makes the picture change under your
    /// finger like the Camera app (see Streamer.applyCameraSettings's doc for why no further debounce).
    private func liveSlider(_ icon: String, _ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, disabled: Bool = false) -> some View {
        VStack(spacing: 2) {
            HStack {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption2.monospacedDigit())
                Spacer()
            }
            .foregroundStyle(.white)
            Slider(value: value, in: range)
                .tint(.white)
                .onChange(of: value.wrappedValue) { _, _ in streamer.applyCameraSettings() }
        }
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }

    private func tap(strong: Bool = false) {
        UIImpactFeedbackGenerator(style: strong ? .heavy : .light).impactOccurred()
    }

    // MARK: First run

    private var registerCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "eyeglasses").font(.system(size: 40))
            Text("Connect your glasses").font(.title3.bold())
            Text("In the Meta AI app: Settings → App Info → tap the version 5× → turn on Developer Mode. Then register this app.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button {
                tap(); streamer.register()
            } label: {
                Label("Register with Meta AI", systemImage: "link").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text(streamer.registration).font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: Chat sheet

    private var chatSheet: some View {
        Group {
            if !chatConfigured {
                VStack(spacing: 12) {
                    Text("No chat source set").font(.headline)
                    Text("Set a channel name in Settings, or connect a platform in Stream Manager and tap “Use for streaming”.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack {
                        Button("Settings") { showChat = false; showSettings = true }
                        Button("Stream Manager") { showChat = false; showManager = true }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chatList
            }
        }
        .padding(.top, 8)
    }

    /// Native, aggregated chat: every origin ChatFeed is running lands in one list, newest at the bottom.
    /// Auto-scrolls on new messages only while the user is already at the bottom — the onAppear/onDisappear
    /// pair on the trailing anchor is "is the bottom on screen right now", no scroll-offset PreferenceKey
    /// needed. Once the user scrolls up to read history, new messages stop yanking them back down.
    private var chatList: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(chat.recent.enumerated()), id: \.offset) { _, event in
                            chatRow(event)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .onAppear { atBottom = true }
                            .onDisappear { atBottom = false }
                    }
                    .padding(.horizontal)
                }
                .dynamicTypeSize(Self.chatSizes[min(chatTextSize, Self.chatSizes.count - 1)])
                .onChange(of: chat.recent.count) { _, _ in
                    guard atBottom else { return }
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            composeBar
        }
    }

    /// `.message` gets full weight — badge, username, message with inline emotes, legible size, generous
    /// spacing for reading one-handed while walking. Everything else (tips/cheers/follows/subs/raids) is
    /// already spoken aloud by Speaker, so it renders smaller and dimmer here — a glance, not a headline.
    @ViewBuilder
    private func chatRow(_ event: ChatEvent) -> some View {
        if event.kind == .message {
            HStack(alignment: .top, spacing: 10) {
                originBadge(event.origin)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.user).font(.subheadline.weight(.semibold))
                    messageText(event).font(.body)
                }
            }
            .padding(.vertical, 10)
        } else {
            HStack(spacing: 8) {
                originBadge(event.origin)
                Text(eventSummary(event)).font(.footnote)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
        }
    }

    private func platformName(_ id: String) -> String { ["kick": "Kick", "twitch": "Twitch", "youtube": "YouTube"][id] ?? id }

    private func originBadge(_ origin: String) -> some View {
        let color: Color = origin == "twitch" ? .purple : origin == "youtube" ? .red : .green
        return Text(origin.isEmpty ? "?" : origin.prefix(1).uppercased())
            .font(.caption2.bold())
            .frame(width: 20, height: 20)
            .foregroundStyle(.white)
            .background(color, in: Circle())
    }

    private func eventSummary(_ e: ChatEvent) -> String {
        switch e.kind {
        case .tip:
            let amount = String(format: "%.2f", Double(e.amountCents) / 100)
            return "\(e.user) tipped $\(amount)" + (e.text.isEmpty ? "" : " — \(e.text)")
        case .cheer: return "\(e.user) cheered \(e.count) bits" + (e.text.isEmpty ? "" : " — \(e.text)")
        case .follow: return "\(e.user) followed"
        case .subscribe: return "\(e.user) subscribed"
        case .raid: return "\(e.user) raided with \(e.count) viewers"
        case .message: return e.text
        }
    }

    /// Inline emotes via Text concatenation: `Text(Image(...))` is the only way to get an image flowing
    /// inside wrapped text instead of breaking out as a separate view — AsyncImage can't sit inside a Text
    /// run since it's a View, not an Image value. An emote still loading (`image(for:)` returns nil while
    /// Emotes fetches and decodes it) renders as an empty run this pass; the row redraws once it lands.
    private func messageText(_ event: ChatEvent) -> Text {
        Emotes.tokenize(event.text, byName: emotes.byName).reduce(Text("")) { partial, run in
            switch run {
            case .text(let s): return partial + Text(s)
            case .emote(let url):
                if let img = emotes.image(for: url) { return partial + Text(img) }
                return partial + Text("")
            }
        }
    }

    private var composeBar: some View {
        VStack(spacing: 8) {
            if sendTargets.count > 1 {
                Picker("Send to", selection: $chatSite) {
                    ForEach(sendTargets, id: \.self) { Text(platformName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 10) {
                // One tap cycles the size, so it's usable without looking for a slider.
                Button { tap(); chatTextSize = (chatTextSize + 1) % Self.chatSizes.count } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("Chat text size")
                TextField("Message", text: $chatText).textFieldStyle(.roundedBorder).onSubmit(sendChat)
                Button(action: sendChat) { Image(systemName: "paperplane.fill") }
                    .disabled(chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    /// Targets whichever platform `chatSite` names, falling back to the first available one if it points
    /// at something not currently configured/connected. Send methods are Platforms' own — this only routes.
    private func sendChat() {
        let text = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let target = sendTargets.contains(chatSite) ? chatSite : (sendTargets.first ?? chatSite)
        chatText = ""
        Task {
            switch target {
            case "twitch": await platforms.twitchSend(text)
            case "youtube": await platforms.ytSend(text)
            default: await platforms.kickSend(text)
            }
        }
    }
}
