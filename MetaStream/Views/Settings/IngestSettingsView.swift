import SwiftUI

struct IngestSettingsView: View {
    @AppStorage("platform") var platform = "kick"
    @AppStorage("rtmpURL") var ingestURL = "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/"
    @AppStorage("streamKey") var streamKey = ""
    @AppStorage("codec") var codec = "auto"
    @AppStorage("bitrateKbps") var bitrateKbps = 4000
    @AppStorage("srtLatencyMs") var srtLatencyMs = 2000
    @AppStorage("chatOrigin") var chatOrigin = "kick"
    @AppStorage("chatChannel") var chatChannel = ""
    @State private var showKey = false

    init() { ChatOriginKey.migrate() }

    // Ingest URLs. Instagram and TikTok hand out a per-stream URL in their own tools, so they stay "custom".
    private static let presets: [String: String] = [
        "kick": "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/",
        "twitch": "rtmps://live.twitch.tv:443/app/",
        "youtube": "rtmps://a.rtmps.youtube.com:443/live2",
        "restream": "rtmp://live.restream.io/live",
    ]
    /// Flat bitrate ceilings a few destinations' ingest is known to reject above, tested/documented
    /// knowledge (README), not queryable from any API -- same footing as the codec table below. Twitch's
    /// is the non-Partner number; this app has no way to know partner status, so it stays conservative.
    /// Platforms not listed (YouTube, Restream, Instagram, TikTok, Custom) don't publish one flat cap the
    /// same way -- YouTube's own guidance scales with resolution up to ~51,000 kbps at 4K60, for instance
    /// -- so rather than fabricate a number for those, they keep genericBitrateCeiling.
    private static let bitrateCeilings: [String: Int] = ["kick": 8000, "twitch": 6000]
    private static let genericBitrateCeiling = 9000
    private static func bitrateCeiling(for platform: String) -> Int { bitrateCeilings[platform] ?? genericBitrateCeiling }

    private static let hints: [String: String] = [
        "kick": "H.264 only, up to 8000 kbps. Transcoding uses the phone's decoder, which iOS stops in the background unless the Picture in Picture window stays open.",
        "twitch": "Up to 6000 kbps, 8000 for Partners. HEVC is Affiliate/Partner only, so Auto sends H.264.",
        "youtube": "Takes the glasses' HEVC untouched over enhanced RTMP, so it also keeps streaming in the background. Create the stream in YouTube Studio first.",
        "restream": "Fans out to every destination set up in the Restream dashboard. Their RTMP ingest is H.264 only (HEVC needs SRT), so Auto transcodes.",
        "instagram": "Open Live Producer on instagram.com (desktop) and copy the stream URL and key here. H.264 only, up to 4000 kbps.",
        "tiktok": "Get the server URL and key from TikTok LIVE Studio and paste both here. H.264 only.",
        "custom": "Any RTMP, RTMPS or SRT server, such as your own relay. Paste an srt:// URL to publish over SRT, which survives packet loss far better on cellular — put the stream key in its streamid query item, since SRT has no separate publish name. Auto sends HEVC untouched; switch to H.264 if your server refuses it.",
    ]

    var body: some View {
        Form {
            Section {
                Picker("Platform", selection: $platform) {
                    Text("Kick").tag("kick"); Text("Twitch").tag("twitch"); Text("YouTube").tag("youtube")
                    Text("Restream").tag("restream"); Text("Instagram").tag("instagram"); Text("TikTok").tag("tiktok")
                    Text("Custom").tag("custom")
                }
                .onChange(of: platform) { _, p in
                    if let url = Self.presets[p] { ingestURL = url } else if p != "custom" { ingestURL = "" }
                    if bitrateKbps > Self.bitrateCeiling(for: p) { bitrateKbps = Self.bitrateCeiling(for: p) }
                }
                TextField("Ingest URL", text: $ingestURL)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                HStack {
                    if showKey {
                        TextField("Stream key", text: $streamKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else {
                        SecureField("Stream key", text: $streamKey)
                    }
                    Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Picker("Video codec", selection: $codec) {
                    Text("Auto").tag("auto"); Text("HEVC (passthrough)").tag("hevc"); Text("H.264 (transcode)").tag("h264")
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Bitrate"); Spacer(); Text(String(bitrateKbps) + " kbps").monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: Binding(get: { Double(bitrateKbps) }, set: { bitrateKbps = Int($0 / 250) * 250 }),
                           in: 1000...Double(Self.bitrateCeiling(for: platform)), step: 250)
                }
                if ingestURL.lowercased().hasPrefix("srt://") {
                    Stepper("SRT buffer \(srtLatencyMs) ms", value: $srtLatencyMs, in: 200...8000, step: 200)
                }
            } header: { Text("Ingest") } footer: {
                Text((Self.hints[platform] ?? "") + "\nAuto picks H.264 for Kick and Twitch (they don't take HEVC) and passthrough elsewhere. H.264 re-encodes on the phone at the bitrate below; HEVC passthrough keeps the glasses' own bitrate.")
            }

            Section("Chat") {
                Picker("Chat origin", selection: $chatOrigin) { Text("Kick").tag("kick"); Text("Twitch").tag("twitch") }
                TextField("Channel name", text: $chatChannel).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        .navigationTitle("Ingest & protocol")
        .navigationBarTitleDisplayMode(.inline)
    }
}
