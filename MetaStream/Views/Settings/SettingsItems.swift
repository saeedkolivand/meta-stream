import Foundation

/// Searchable individual settings, by screen. A `key:` item is a plain switch the search results flip inline: its key and
/// default are the exact ones the screen's own @AppStorage uses. Switches with side effects in their screen (dual camera,
/// Center Stage, glasses, remote server) or hardware gating (manual exposure...) have no key and open their screen instead.
enum SettingsItems {
    static var all: [SettingsItem] {
        stream + camera + chatItems + appBot + money + rest
    }

    private static var stream: [SettingsItem] {
        [
            SettingsItem("Platform", "ingest", "kick twitch youtube restream instagram tiktok custom destination"),
            SettingsItem("Ingest URL", "ingest", "rtmp rtmps srt srtla server"),
            SettingsItem("Stream key", "ingest", "password secret"),
            SettingsItem("Video codec", "ingest", "hevc h264 h.265 transcode passthrough"),
            SettingsItem("Bitrate", "ingest", "kbps quality"),
            SettingsItem("SRT buffer", "ingest", "latency srt"),
            SettingsItem("Bonding roles", "ingest", "srtla wifi ethernet cellular backup"),
            SettingsItem("Use Meta glasses", "glasses", "ray-ban wearables"),
            SettingsItem("Glasses resolution", "glasses", "video low medium high"),
            SettingsItem("Glasses frame rate", "glasses", "fps"),
            SettingsItem("Microphone", "audio", "mic input bluetooth voice isolation"),
            SettingsItem("Mute microphone", "audio", "mic"),
            SettingsItem("Mix volume", "audio", "alert clip sound loudness"),
            SettingsItem("Alert sound", "audio", "chime"),
            SettingsItem("Soundboard", "audio", "sounds effects"),
            SettingsItem("Privacy blur", "privacy", "pixellate censor", key: "blurOn"),
            SettingsItem("Blur faces", "privacy", "", key: "blurFaces", on: true),
            SettingsItem("Blur text and licence plates", "privacy", "license plate number", key: "blurText", on: true),
            SettingsItem("Blur QR codes and barcodes", "privacy", "", key: "blurBarcodes", on: true)
        ]
    }

    private static var camera: [SettingsItem] {
        [
            SettingsItem("Camera (back or front)", "camera", "fallback lens selfie"),
            SettingsItem("Lens", "camera", "wide ultra wide telephoto"),
            SettingsItem("Zoom", "camera", ""),
            SettingsItem("Focus mode", "camera", "pro controls autofocus manual lens position"),
            SettingsItem("Smooth autofocus", "camera", "pro controls"),
            SettingsItem("Face-driven autofocus", "camera", "pro controls", key: "camFaceDrivenAutoFocus", on: true),
            SettingsItem("Manual exposure", "camera", "pro controls iso shutter bias ev"),
            SettingsItem("Low-light boost", "camera", "pro controls night"),
            SettingsItem("Manual white balance", "camera", "pro controls temperature tint kelvin"),
            SettingsItem("HDR", "camera", "pro controls"),
            SettingsItem("Mirror", "camera", "flip selfie", key: "camMirrored"),
            SettingsItem("Geometric distortion correction", "camera", "pro controls gdc fisheye"),
            SettingsItem("Torch", "camera", "pro controls light flash"),
            SettingsItem("Dual camera", "camera", "picture in picture front back"),
            SettingsItem("Color look and LUT", "camera", "pro controls brightness contrast saturation warmth filter"),
            SettingsItem("Center Stage", "camera", "pro controls front camera framing"),
            SettingsItem("Rule-of-thirds grid", "camera", "pro controls composition", key: "camGridOn"),
            SettingsItem("Level", "camera", "pro controls horizon", key: "camLevelOn"),
            SettingsItem("Resolution", "camera", "720p 1080p phone"),
            SettingsItem("Frame rate", "camera", "fps"),
            SettingsItem("Stabilisation", "camera", "stabilization"),
            SettingsItem("Live control strip", "camera", "customise buttons")
        ]
    }

    private static var chatItems: [SettingsItem] {
        [
            SettingsItem("Chat origin", "chat", "kick twitch channel"),
            SettingsItem("Channel name", "chat", "chat"),
            SettingsItem("Voice", "chat", "tts text to speech premium"),
            SettingsItem("AI moderation", "chat", "dont read apple intelligence hate"),
            SettingsItem("Names not to read", "chat", "dont read ignore mute"),
            SettingsItem("Blocked words", "chat", "dont read slur filter"),
            SettingsItem("Read chat messages", "chat", "tts", key: "ttsMessagesOn", on: true),
            SettingsItem("Read tips and bits", "chat", "tts donations", key: "ttsTipsOn", on: true),
            SettingsItem("Read follows", "chat", "tts", key: "ttsFollowsOn", on: true),
            SettingsItem("Read subscriptions", "chat", "tts subs", key: "ttsSubsOn", on: true),
            SettingsItem("Read raids", "chat", "tts", key: "ttsRaidsOn", on: true),
            SettingsItem("Reading speed", "chat", "tts rate"),
            SettingsItem("Read tips from", "chat", "minimum amount"),
            SettingsItem("Read Kick chat", "chat", "voice", key: "voiceKick", on: true),
            SettingsItem("Read Twitch chat", "chat", "voice", key: "voiceTwitch", on: true),
            SettingsItem("Read YouTube chat", "chat", "voice", key: "voiceYouTube", on: true),
            SettingsItem("Saved commands", "commands", "bot shortcuts slash"),
            SettingsItem("Commands on Lock Screen", "commands", "live card buttons", key: "lockScreenCommands"),
            SettingsItem("Kick sign-in for /clear", "commands", "session"),
            SettingsItem("Bot names", "bots", "nightbot list"),
            SettingsItem("Read bot messages", "bots", "tts announcements"),
            SettingsItem("Announcement trigger words", "bots", "highlight")
        ]
    }

    private static var appBot: [SettingsItem] {
        let commands = ["Location", "Speed", "Distance", "Weather", "Battery", "Uptime", "Goal", "Donate", "Song", "Commands"]
        let toggles = commands.map {
            SettingsItem("!" + $0.lowercased() + " command", "appbot", "viewer chat", key: "botCmd" + $0, on: true)
        }
        return toggles + [
            SettingsItem("App bot on Kick", "appbot", "chat bot", key: "botKick"),
            SettingsItem("App bot on Twitch", "appbot", "chat bot", key: "botTwitch"),
            SettingsItem("Bot test mode", "appbot", "offline try", key: "botTestMode"),
            SettingsItem("Twitch bot account", "appbot", "connect second account"),
            SettingsItem("Scene notices", "appbot", "messages brb starting ending", key: "botNotices", on: true),
            SettingsItem("Thank-yous", "appbot", "messages follow sub raid donation", key: "botThanks", on: true),
            SettingsItem("Hide location", "appbot", "privacy", key: "botHideLocation"),
            SettingsItem("Bot timers", "appbot", "timers repeat message", key: "botTimersOn"),
            SettingsItem("Donate answer", "appbot", "messages !donate tip support")
        ]
    }

    private static var money: [SettingsItem] {
        [
            SettingsItem("Goal title and target", "goal", "donation raised"),
            SettingsItem("Goal currency", "goal", "toman euro dollar"),
            SettingsItem("Toman rate", "goal", "rates nobitex exchange refresh"),
            SettingsItem("Values (sub, Bit)", "goal", "rates worth dollars twitch kick youtube membership"),
            SettingsItem("Add amount", "goal", "cash bank transfer manual"),
            SettingsItem("Test donation", "goal", "alert"),
            SettingsItem("Recent donations", "goal", "refund remove"),
            SettingsItem("Donofa", "sources", "api key widget"),
            SettingsItem("Reymit", "sources", "api token overlay"),
            SettingsItem("StreamElements", "sources", "jwt token"),
            SettingsItem("Donito", "sources", "overlay link"),
            SettingsItem("Donate page URL", "donatepage", "cloudflare goal token"),
            SettingsItem("Donate page key", "donatepage", "secret")
        ]
    }

    private static var rest: [SettingsItem] {
        [
            SettingsItem("Scenes", "overlays", "layers layout"),
            SettingsItem("Widgets", "overlays", "chat alerts now playing text"),
            SettingsItem("Stinger", "overlays", "transition video"),
            SettingsItem("Transitions", "transitions", "fade cut"),
            SettingsItem("Scene roles", "transitions", "brb starting ending"),
            SettingsItem("Auto-rotate", "transitions", "orientation"),
            SettingsItem("GPS share", "transitions", "location"),
            SettingsItem("OBS import", "transitions", "overlay pack"),
            SettingsItem("Theme", "theme", "colour color"),
            SettingsItem("Instagram story layout", "theme", "share card"),
            SettingsItem("Kick", "accounts", "connect login streaming"),
            SettingsItem("Twitch", "accounts", "connect login streaming"),
            SettingsItem("YouTube", "accounts", "connect login streaming"),
            SettingsItem("Restream", "accounts", "connect login streaming"),
            SettingsItem("Live post", "telegram", "channel", key: "telegramOn"),
            SettingsItem("Telegram bot token", "telegram", "botfather"),
            SettingsItem("Telegram channel", "telegram", ""),
            SettingsItem("Telegram language", "telegram", "persian farsi english"),
            SettingsItem("Show donation total in recap", "telegram", "", key: "telegramShowTotal", on: true),
            SettingsItem("Big donation moment", "telegram", "euro"),
            SettingsItem("Moment pings", "telegram", "raid spike", key: "telegramPings", on: true),
            SettingsItem("Show city", "telegram", "location", key: "telegramShowCity"),
            SettingsItem("Connect Spotify", "spotify", "now playing song premium"),
            SettingsItem("obs-websocket server", "remote", "stream deck touch portal streamer.bot"),
            SettingsItem("Remote password", "remote", "obs"),
            SettingsItem("Keep screen awake", "diagnostics", "sleep lock", key: "keepAwake", on: true),
            SettingsItem("Logs", "diagnostics", "debug"),
            SettingsItem("Version", "diagnostics", "team id registration about")
        ]
    }
}
