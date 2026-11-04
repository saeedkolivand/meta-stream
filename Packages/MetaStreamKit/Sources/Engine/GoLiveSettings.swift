// Going live from the saved settings (Go Live button, OBS remote StartStream) and the codec rule they imply.
import Foundation

extension Streamer {
    /// Go Live with the saved settings: the Go Live button and the remote's StartStream both land here.
    /// Keys and defaults mirror the old @AppStorage declarations in GoLiveControlsView.
    func goLiveFromSettings() {
        let d = UserDefaults.standard
        func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
        goLive(url: d.string(forKey: "rtmpURL") ?? "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/",
               key: d.string(forKey: "streamKey") ?? "", micUID: d.string(forKey: "micUID") ?? "",
               fallbackPosition: d.string(forKey: "fallbackCamera") == "front" ? .front : .back,
               bitrateKbps: int("bitrateKbps", 4000), codec: Self.codecFromSettings, srtLatencyMs: int("srtLatencyMs", 2000),
               quality: .init(height: int("phoneHeight", 720), landscape: d.bool(forKey: "phoneLandscape"), fps: int("phoneFps", 30),
                              stabilization: d.string(forKey: "phoneStabilization") ?? "off"))
    }

    /// auto: only YouTube (enhanced RTMP) and custom servers take the glasses' HEVC untouched. Kick, Restream,
    /// Instagram and TikTok are H.264-only ingests, and Twitch gates HEVC behind Affiliate, so they get a transcode.
    static var codecFromSettings: String {
        let settings = UserDefaults.standard
        let codecPref = settings.string(forKey: "codec") ?? "auto", platformPref = settings.string(forKey: "platform") ?? "kick"
        let ingestURL = settings.string(forKey: "rtmpURL") ?? ""
        // adr/0001: blur has to decode every frame to obscure it, so it forces a transcode and
        // outranks even an explicit HEVC choice — you cannot blur a frame you never decode.
        // Dual camera is the same story: the face-cam overlay (and glasses video, which only reaches the mixer
        // as decoded frames) is composited on the phone, so it re-encodes whatever codec was picked.
        // Precedence: blur / dual camera > explicit codec > protocol capability > destination table.
        // A non-neutral glasses Look is the same story: passthrough can't be graded (adr/0001).
        if settings.bool(forKey: "blurOn") || settings.bool(forKey: "dualCam") || !Look.load("glasses").isNeutral { return "h264" }
        guard codecPref == "auto" else { return codecPref }
        // SRT carries whatever the server decodes, and passthrough is the entire reason to use it:
        // no transcode means no PiP window needed to keep streaming in the background.
        if ingestURL.lowercased().hasPrefix("srt") { return "hevc" }
        return ["youtube", "custom"].contains(platformPref) ? "hevc" : "h264"
    }
}
