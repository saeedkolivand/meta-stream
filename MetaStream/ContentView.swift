import MWDATCore
import SwiftUI

// MARK: - Live screen

struct ContentView: View {
    @EnvironmentObject var streamer: Streamer
    @EnvironmentObject var speaker: Speaker
    @EnvironmentObject var chat: ChatFeed
    @EnvironmentObject var platforms: Platforms
    @EnvironmentObject var privacy: Privacy
    @AppStorage("keepAwake") var keepAwake = true
    @AppStorage("camLevelOn") var camLevelOn = false

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

    private var phoneCamControllable: Bool { streamer.source == "phone" && streamer.manualSource != "external" }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PreviewContainerView(levelMonitor: levelMonitor, focusTap: $focusTap, aeafLocked: $aeafLocked, pinchStartZoom: $pinchStartZoom)
                .ignoresSafeArea()

            VStack {
                HUDView(showStatus: $showStatus, showManager: $showManager, showChat: $showChat, showCameraControls: $showCameraControls)
                Spacer()
                GoLiveControlsView(codec: vm.codec, showChat: $showChat, showSettings: $showSettings)
            }
            .padding(.horizontal)

            if Streamer.glassesConfigured, streamer.registration != "registered" { registerCard }

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
        }
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
