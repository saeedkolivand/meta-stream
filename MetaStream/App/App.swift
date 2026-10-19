import SwiftUI
import MWDATCore

@main
struct MetaStreamApp: App {
    @StateObject private var streamer = Streamer()
    @StateObject private var platforms = Platforms()
    @StateObject private var speaker = Speaker()
    // @State, not @StateObject: the App must not re-evaluate per chat message. Views that show chat read it from the environment.
    @State private var chat = ChatFeed()
    @StateObject private var privacy = Privacy()
    // Cold launch only: App state survives rotation and backgrounding.
    @State private var showSplash = true
    @AppStorage("gpsShare") private var gpsShare = false

    init() {
        do { try Wearables.configure() }
        catch { applog("ui", "Wearables.configure failed: \(error.localizedDescription)", error: true) }
    }

    /// iPhone sharing GPS with the iPad and not live: GPSOnlyView, camera off (Streamer.setGPSOnly).
    private var gpsOnly: Bool { gpsShare && Streamer.gpsOnlyWanted(live: streamer.live) }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if gpsOnly {
                    GPSOnlyView()
                } else {
                    ContentView(chat: chat)
                        .environmentObject(streamer)
                        .environmentObject(platforms)
                        .environmentObject(speaker)
                        .environmentObject(chat)
                        .environmentObject(privacy)
                }
                if showSplash { SplashView { showSplash = false } }
            }
            // Streamer speaks connection changes on Speaker's System lane (never muted).
            .onAppear {
                streamer.speaker = speaker; streamer.privacy = privacy
                AppBot.shared.streamer = streamer; AppBot.shared.platforms = platforms
                if gpsShare { GPSShare.shared.setEnabled(true) }
                ObsServer.shared.sync(streamer)
                BotCommand.addClearOnce()
                Rates.shared.start()
                DonationHub.shared.start(chat: chat)
                GoalStore.shared.onReached = { speaker.speakSystem("Goal reached"); AppBot.shared.goalReached(GoalStore.shared.config.title) }
                StreamActivityActions.sendCommand = { id in
                    guard UserDefaults.standard.bool(forKey: "lockScreenCommands"),
                          let c = BotCommand.stored().first(where: { $0.id.uuidString == id }) else { return }
                    Task { await c.send(platforms, chat: chat) }
                }
            }
            .onChange(of: gpsOnly) { _, on in streamer.setGPSOnly(on) }
            .task {
                // Here, not in ContentView: GPS-only mode unmounts ContentView, and cancelling this loop would end
                // chat.events for good. ponytail: one consumer for the app's lifetime. ChatFeed buffers, Speaker
                // bounds its own lanes, so nothing here needs backpressure handling.
                for await e in chat.events {
                    // Every money event counts toward the goal once (a donation site's own events are already recorded).
                    // DonationHub records donofa/reymit/streamelements itself (own ids): the alert must not count twice.
                    if !["test-donation", "donofa", "reymit", "streamelements", "donito"].contains(e.origin), let m = DonationPrices.money(e) {
                        GoalStore.shared.record(key: e.origin + ":" + (e.id.isEmpty ? UUID().uuidString : e.id), source: e.origin, money: m, at: e.at, note: e.goalNote)
                    }
                    speaker.speak(e)
                    AppBot.shared.handle(e)
                    if e.kind == .message, !e.flagged, BotList.isAnnouncement(user: e.user, text: e.text) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
            .onOpenURL { url in
                Task {
                    do { _ = try await Wearables.shared.handleUrl(url) }
                    catch { applog("ui", "handleUrl failed: \(error.localizedDescription)", error: true) }
                }
            }
        }
        .commands { StreamCommands(streamer: streamer, speaker: speaker) }
    }
}
