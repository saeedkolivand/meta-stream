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
                if gpsShare { GPSShare.shared.setEnabled(true) }
            }
            .onChange(of: gpsOnly) { _, on in streamer.setGPSOnly(on) }
            .task {
                // Here, not in ContentView: GPS-only mode unmounts ContentView, and cancelling this loop would end
                // chat.events for good. ponytail: one consumer for the app's lifetime. ChatFeed buffers, Speaker
                // bounds its own lanes, so nothing here needs backpressure handling.
                for await e in chat.events { speaker.speak(e) }
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
