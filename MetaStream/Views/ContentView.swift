import MWDATCore
import SwiftUI

// MARK: - Live screen

struct ContentView: View {
    @EnvironmentObject var streamer: Streamer
    @EnvironmentObject var speaker: Speaker
    /// Plain reference, not observed: a chat message must not rebuild this screen. Child views that show chat observe
    /// it through the environment.
    let chat: ChatFeed
    @EnvironmentObject var platforms: Platforms
    @EnvironmentObject var privacy: Privacy
    @AppStorage("keepAwake") var keepAwake = true
    @AppStorage("camLevelOn") var camLevelOn = false
    @AppStorage("gpsShare") private var gpsShare = false
    @Environment(\.scenePhase) private var phase

    @StateObject private var vm = StreamViewModel()
    @StateObject private var emotes = Emotes()
    @StateObject private var levelMonitor = LevelMonitor()
    @State private var showSettings = false
    @State private var showChat = false
    @State private var showStatus = false
    @State private var showManager = false
    @State private var showCameraControls = false
    @State private var photoFlash = false
    @State private var focusTap: CGPoint?
    @State private var aeafLocked = false
    @State private var pinchStartZoom: Double?
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var controlsVisible = true
    @State private var lastTouch = Date.now

    private var phoneCamControllable: Bool { streamer.source == "phone" && streamer.manualSource != "external" }

    /// Anything presented keeps the controls up; otherwise they fade after 5 s without a touch.
    private var controlsPinned: Bool { showSettings || showChat || showManager || showStatus || showCameraControls }
    private var controlsShown: Bool { controlsVisible || controlsPinned }

    private func touch() {
        lastTouch = .now
        if !controlsVisible { controlsVisible = true }
    }

    /// Red pill so a muted mic / hidden camera is not forgotten while the controls are faded out.
    @ViewBuilder private var hiddenWarning: some View {
        let parts: [(String, String)] = (streamer.muted ? [("mic.slash.fill", "Muted")] : [])
            + (streamer.cameraOff ? [("video.slash.fill", "Camera hidden")] : [])
        if !controlsShown, !parts.isEmpty {
            VStack {
                HStack(spacing: 6) {
                    ForEach(parts, id: \.1) { Image(systemName: $0.0) }
                    Text(parts.map(\.1).joined(separator: " · "))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.red, in: Capsule())
                Spacer()
            }
            .padding(.top, 8)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// HUD, bottom controls and (compact width) the left-edge mic/camera/blur rail; fades out as one.
    private var controlsLayer: some View {
        ZStack {
            VStack {
                HUDView(showStatus: $showStatus, showManager: $showManager, showChat: $showChat, showCameraControls: $showCameraControls)
                Spacer()
                GoLiveControlsView(codec: vm.codec, showChat: $showChat, showSettings: $showSettings)
            }
            .padding(.horizontal)

            // Compact width: mic/camera/blur live in a left-edge rail (right edge belongs to the camera strip).
            if hSize == .compact {
                HStack {
                    VStack(spacing: 10) { QuickControls(size: 44) }.padding(.leading, 10)
                    Spacer()
                }
            }
        }
        .opacity(controlsShown ? 1 : 0)
        .allowsHitTesting(controlsShown)
    }

    /// Preview, controls and the auto-hide behaviour; split from `body` so the type checker copes with the modifier chain.
    private var stage: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PreviewContainerView(levelMonitor: levelMonitor, focusTap: $focusTap, aeafLocked: $aeafLocked, pinchStartZoom: $pinchStartZoom)
                .ignoresSafeArea()

            controlsLayer

            // Only nag once the user actually picks glasses: phone/external-camera streaming never needs Meta.
            if Streamer.glassesConfigured, streamer.manualSource == "glasses", streamer.registration != "registered" { registerCard }

            if photoFlash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            // Trailing edge, vertically centered: stays clear of the HUD row (top), GO LIVE (bottom),
            // and the preview centre, while staying thumb-reachable one-handed.
            if showCameraControls, phoneCamControllable {
                HStack {
                    Spacer()
                    CameraControlStripView().padding(.trailing, 10)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Swallows the first tap while hidden so it only reveals (no tap-to-focus, no stray button hits).
            if !controlsShown {
                Color.clear.contentShape(Rectangle()).ignoresSafeArea().onTapGesture { touch() }
            }
            hiddenWarning
        }
        .animation(.easeInOut(duration: 0.3), value: controlsShown)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in if controlsShown { touch() } })
        .task(id: lastTouch) {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            controlsVisible = false
        }
        .onChange(of: controlsPinned) { _, _ in touch() }
        .onChange(of: phase) { _, p in gpsOnlyBackground(p) }   // here, not in body: body's chain is at the type-checker's limit
    }

    /// Background location keeps the app alive only to share GPS with the iPad (GPSShare): chat, its read-aloud and the
    /// level sensor stop until the app is back, so the phone isn't reading chat and iOS has less reason to close it.
    private func gpsOnlyBackground(_ p: ScenePhase) {
        guard gpsShare, !streamer.live else { return }
        if p == .background {
            chat.stop(); levelMonitor.stop()
            applog("location", "background: sharing GPS only, chat stopped")
        } else if p == .active {
            vm.startChat(chat: chat, platforms: platforms, emotes: emotes, speaker: speaker)
            if camLevelOn { levelMonitor.start() }
        }
    }

    var body: some View {
        stage
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showManager) { StreamManagerView() }
        .sheet(isPresented: $showChat) {
            ChatSheetView(vm: vm, emotes: emotes, showChat: $showChat, showSettings: $showSettings, showManager: $showManager)
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
        .onAppear { vm.startChat(chat: chat, platforms: platforms, emotes: emotes, speaker: speaker); vm.applyBlur(privacy: privacy, streamer: streamer); if camLevelOn { levelMonitor.start() } }
        .onChange(of: vm.chatChannel) { _, _ in vm.startChat(chat: chat, platforms: platforms, emotes: emotes, speaker: speaker) }
        .onChange(of: vm.voiceKick) { _, _ in vm.startChat(chat: chat, platforms: platforms, emotes: emotes, speaker: speaker) }
        .onChange(of: vm.voiceTwitch) { _, _ in vm.startChat(chat: chat, platforms: platforms, emotes: emotes, speaker: speaker) }
        .onChange(of: vm.voiceYouTube) { _, _ in vm.startChat(chat: chat, platforms: platforms, emotes: emotes, speaker: speaker) }
        .onChange(of: platforms.twitchConnected) { _, _ in vm.startChat(chat: chat, platforms: platforms, emotes: emotes, speaker: speaker) }
        .onChange(of: platforms.ytConnected) { _, _ in vm.startChat(chat: chat, platforms: platforms, emotes: emotes, speaker: speaker) }
        .onChange(of: vm.blurOn) { _, _ in vm.applyBlur(privacy: privacy, streamer: streamer) }
        .onChange(of: vm.blurFaces) { _, _ in vm.applyBlur(privacy: privacy, streamer: streamer) }
        .onChange(of: vm.blurText) { _, _ in vm.applyBlur(privacy: privacy, streamer: streamer) }
        .onChange(of: vm.blurBarcodes) { _, _ in vm.applyBlur(privacy: privacy, streamer: streamer) }
        // Glasses (re)connecting can flip the source out from under an open strip -- nothing left to control.
        .onChange(of: streamer.source) { _, s in if s != "phone" { showCameraControls = false; aeafLocked = false } }
        .onChange(of: streamer.manualSource) { _, s in if s == "external" { showCameraControls = false; aeafLocked = false } }
        .onChange(of: camLevelOn) { _, on in on ? levelMonitor.start() : levelMonitor.stop() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onAppear {
            let c = streamer.overlays.context
            c.chat = chat; c.emotes = emotes; c.streamer = streamer; c.platforms = platforms
            streamer.updateSceneRotation()
        }
        .onChange(of: keepAwake) { _, v in UIApplication.shared.isIdleTimerDisabled = v }
        .onChange(of: streamer.lastPhotoAt) { _, _ in
            withAnimation(.easeOut(duration: 0.1)) { photoFlash = true }
            Task { try? await Task.sleep(for: .milliseconds(120)); withAnimation(.easeIn(duration: 0.3)) { photoFlash = false } }
        }
    }

    // MARK: First run

    private var registerCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "eyeglasses").font(.system(size: 40))
            Text("Connect your glasses").font(.title3.bold())
            Text("In the Meta AI app: Settings → App Info → tap the version 5× → turn on Developer Mode. Then register this app.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button {
                hapticTap(); streamer.register()
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
}
