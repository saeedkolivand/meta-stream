// {tokens} for on-stream text, resolved from the live app state once per second by the live text widget.
import UIKit

@MainActor
enum WidgetVariables {
    /// For the editor's insert menu, in menu order.
    static let tokens: [(token: String, label: String)] = [
        ("{time}", "Time"), ("{date}", "Date"), ("{uptime}", "Live time"), ("{viewers}", "Viewers"), ("{bitrate}", "Bitrate"),
        ("{battery}", "Battery"), ("{speed}", "Speed"), ("{distance}", "Distance"), ("{city}", "City"), ("{weather}", "Weather"),
        ("{follower}", "Latest follower"), ("{sub}", "Latest sub"), ("{countdown}", "Starting countdown"),
        ("{song}", "Spotify song"), ("{artist}", "Spotify artist")
    ]

    static func needsLocation(_ template: String) -> Bool {
        ["{speed}", "{distance}", "{city}", "{weather}"].contains { template.contains($0) }
    }

    static func needsSpotify(_ template: String) -> Bool { template.contains("{song}") || template.contains("{artist}") }

    /// Only tokens present in the template are evaluated, so e.g. battery monitoring stays off unless {battery} is used.
    static func resolve(_ template: String, _ ctx: WidgetContext) -> String {
        guard template.contains("{") else { return template }
        var out = template
        for (token, _) in tokens where out.contains(token) {
            out = out.replacingOccurrences(of: token, with: value(token, ctx))
        }
        return out
    }

    private static func value(_ token: String, _ ctx: WidgetContext) -> String {
        switch token {
        case "{time}": return Date().formatted(date: .omitted, time: .shortened)
        case "{date}": return Date().formatted(date: .abbreviated, time: .omitted)
        case "{uptime}": return uptime(ctx.streamer?.liveSince)
        case "{viewers}":
            guard let p = ctx.platforms else { return "0" }
            return String(p.kickViewers + p.twitchViewers + p.ytViewers)
        case "{bitrate}": return "\(ctx.streamer?.currentBitrateKbps ?? 0) kbps"
        case "{battery}":
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            return level < 0 ? "--" : "\(Int((level * 100).rounded()))%"
        default: return socialValue(token, ctx)
        }
    }

    /// The location, weather, chat and Spotify tokens.
    private static func socialValue(_ token: String, _ ctx: WidgetContext) -> String {
        switch token {
        case "{speed}": return WidgetLocation.shared.speedText
        case "{distance}": return WidgetLocation.shared.distanceText(since: ctx.streamer?.liveSince)
        case "{city}": return WidgetLocation.shared.cityText
        case "{weather}": return WidgetWeather.shared.text
        case "{follower}": return clean(ctx.chat?.lastFollower ?? "")
        case "{sub}": return clean(ctx.chat?.lastSubscriber ?? "")
        case "{countdown}": return ctx.streamer?.countdownText ?? ""
        case "{song}": return SpotifyNowPlaying.shared.track?.title ?? ""
        case "{artist}": return SpotifyNowPlaying.shared.track?.artist ?? ""
        default: return token
        }
    }

    /// A name with a slur or blocked word never goes on stream.
    private static func clean(_ name: String) -> String {
        Speaker.isBlocked(name, extra: UserDefaults.standard.string(forKey: "ttsBlocked") ?? "") ? "" : name
    }

    private static func uptime(_ since: Date?) -> String {
        guard let since else { return "00:00" }
        let s = max(0, Int(Date().timeIntervalSince(since)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
