import Chat
import CoreUI
import Engine
import Platforms
import Privacy
import Speech
import SwiftUI

/// Live-screen state + routing: codec choice, chat origins, chat start/stop, outgoing send and blur.
/// Owns the @AppStorage keys ContentView used to hold directly; duplicates of the same keys in child
/// views stay in sync through UserDefaults, so nothing here needs binding plumbing.
@MainActor
final class StreamViewModel: ObservableObject {
    @AppStorage("rtmpURL") var ingestURL = "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/"
    @AppStorage("streamKey") var streamKey = ""
    @AppStorage("chatOrigin") var chatOrigin = "kick"
    @AppStorage("voiceKick") var voiceKick = true
    @AppStorage("voiceTwitch") var voiceTwitch = true
    @AppStorage("voiceYouTube") var voiceYouTube = true
    @AppStorage("dualCam") var dualCamOn = false
    @AppStorage("blurOn") var blurOn = false
    @AppStorage("blurFaces") var blurFaces = true
    @AppStorage("blurText") var blurText = true
    @AppStorage("blurBarcodes") var blurBarcodes = true
    @AppStorage("chatChannel") var chatChannel = ""
    @AppStorage("codec") var codecPref = "auto"
    @AppStorage("platform") var platformPref = "kick"

    /// One-line result of the last slash command, shown above the compose bar.
    @Published var slashNote = ""

    init() { ChatOriginKey.migrate() }

    /// The engine's codec rule over these same settings (Streamer.codecFromSettings); here so the views re-read it when
    /// any of them changes.
    var codec: String { Streamer.codecFromSettings }

    /// Platforms an outgoing message can actually go to right now - the segmented picker in the compose
    /// bar only ever shows these, and `sendChat()` falls back to the first one if `chatOrigin` points at a
    /// platform that isn't configured/connected.
    func sendOrigins(twitchConnected: Bool, ytConnected: Bool) -> [String] {
        var origins: [String] = []
        if !chatChannel.isEmpty { origins.append("kick") }
        if twitchConnected { origins.append("twitch") }
        if ytConnected { origins.append("youtube") }
        return origins
    }

    /// Targets whichever platform `chatOrigin` names, falling back to the first available one if it points
    /// at something not currently configured/connected. Send methods are Platforms' own — this only routes.
    func sendChat(_ text: String, platforms: Platforms, chat: ChatFeed) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let origins = sendOrigins(twitchConnected: platforms.twitchConnected, ytConnected: platforms.ytConnected)
        let target = origins.contains(chatOrigin) ? chatOrigin : (origins.first ?? chatOrigin)
        slashNote = ""
        if let c = SlashCommand.parse(trimmed) {   // never posted, whatever the outcome
            slashNote = target == "youtube" ? "Slash commands aren't supported on YouTube" : await SlashRunner(p: platforms, chat: chat, origin: target).run(c.name, c.args)
            return
        }
        switch target {
        case "twitch": await platforms.twitchSend(trimmed)
        case "youtube": await platforms.ytSend(trimmed)
        default: await platforms.kickSend(trimmed)
        }
    }

    /// Starts every enabled origin that has what it needs. Kick needs only a slug; Twitch and YouTube
    /// need a connected account. Each origin is owned by exactly one feed, so nothing arrives twice.
    func startChat(chat: ChatFeed, platforms: Platforms, emotes: Emotes, speaker: Speaker) {
        var origins = 0
        if voiceKick, !chatChannel.isEmpty { chat.start(kickSlug: chatChannel); origins += 1 } else { chat.stopKick() }
        if voiceTwitch, platforms.twitchConnected { chat.startTwitch(platforms: platforms); origins += 1 } else { chat.stopTwitch() }
        if voiceYouTube, platforms.ytConnected { chat.startYouTube(platforms: platforms); origins += 1 } else { chat.stopYouTube() }
        // Only prefix "on Kick, …" when more than one origin is live — otherwise it's noise on every line.
        speaker.showOrigin = origins > 1
        let kickSlug = voiceKick && !chatChannel.isEmpty ? chatChannel : nil
        Task { await emotes.load(twitchID: platforms.twitchConnected ? platforms.twitchUserID : nil, kickSlug: kickSlug) }
    }

    /// Privacy exposes plain vars, not @Published — a published hot path would cost a MainActor hop on
    /// every decoded frame. So settings are written through here instead of bound.
    func applyBlur(privacy: Privacy, streamer: Streamer) {
        privacy.enabled = blurOn
        privacy.options = .init(faces: blurFaces, text: blurText, barcodes: blurBarcodes)
        streamer.applyDualCamLayout()   // face-cam window hides the moment blur turns on -- see Streamer.blurWanted
    }
}
