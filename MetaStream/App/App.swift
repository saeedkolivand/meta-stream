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

    init() {
        do { try Wearables.configure() }
        catch { applog("ui", "Wearables.configure failed: \(error.localizedDescription)", error: true) }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(chat: chat)
                    .environmentObject(streamer)
                    .environmentObject(platforms)
                    .environmentObject(speaker)
                    .environmentObject(chat)
                    .environmentObject(privacy)
                    // Streamer speaks connection changes on Speaker's System lane (never muted).
                    .onAppear {
                        streamer.speaker = speaker; streamer.privacy = privacy
                        if UserDefaults.standard.bool(forKey: "gpsShare") { GPSShare.shared.setEnabled(true) }
                    }
                    .onOpenURL { url in
                        Task {
                            do { _ = try await Wearables.shared.handleUrl(url) }
                            catch { applog("ui", "handleUrl failed: \(error.localizedDescription)", error: true) }
                        }
                    }
                if showSplash { SplashView { showSplash = false } }
            }
        }
        .commands { StreamCommands(streamer: streamer, speaker: speaker) }
    }
}
