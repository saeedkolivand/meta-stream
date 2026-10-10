import SwiftUI
import MWDATCore

@main
struct MetaStreamApp: App {
    @StateObject private var streamer = Streamer()
    @StateObject private var platforms = Platforms()
    @StateObject private var speaker = Speaker()
    @StateObject private var chat = ChatFeed()
    @StateObject private var privacy = Privacy()

    init() {
        do { try Wearables.configure() }
        catch { applog("ui", "Wearables.configure failed: \(error.localizedDescription)", error: true) }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(streamer)
                .environmentObject(platforms)
                .environmentObject(speaker)
                .environmentObject(chat)
                .environmentObject(privacy)
                // Streamer speaks connection changes on Speaker's System lane (never muted).
                .onAppear { streamer.speaker = speaker; streamer.privacy = privacy }
                .onOpenURL { url in
                    Task {
                        do { _ = try await Wearables.shared.handleUrl(url) }
                        catch { applog("ui", "handleUrl failed: \(error.localizedDescription)", error: true) }
                    }
                }
        }
    }
}
