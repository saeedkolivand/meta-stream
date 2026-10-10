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

    init() { ChatOriginKey.migrate() }

    /// auto: only YouTube (enhanced RTMP) and custom servers take the glasses' HEVC untouched. Kick, Restream,
    /// Instagram and TikTok are H.264-only ingests, and Twitch gates HEVC behind Affiliate, so they get a transcode.
    var codec: String {
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
    func sendChat(_ text: String, platforms: Platforms) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let origins = sendOrigins(twitchConnected: platforms.twitchConnected, ytConnected: platforms.ytConnected)
        let target = origins.contains(chatOrigin) ? chatOrigin : (origins.first ?? chatOrigin)
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
        Task { await emotes.load(twitchID: platforms.twitchConnected ? platforms.twitchUserID : nil) }
    }

    /// Privacy exposes plain vars, not @Published — a published hot path would cost a MainActor hop on
    /// every decoded frame. So settings are written through here instead of bound.
    func applyBlur(privacy: Privacy, streamer: Streamer) {
        privacy.enabled = blurOn
        privacy.options = .init(faces: blurFaces, text: blurText, barcodes: blurBarcodes)
        streamer.applyDualCamLayout()   // face-cam window hides the moment blur turns on -- see Streamer.blurWanted
    }
}
