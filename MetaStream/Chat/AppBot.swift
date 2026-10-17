import Foundation
import UIKit

/// A message the app bot repeats on a schedule while live (Settings › App bot). The list lives in AppStorage("botTimers") as JSON.
struct AppTimer: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var minutes = 15   // at least 5, see AppBot.timerDue

    static func decode(_ raw: String) -> [AppTimer] { (try? JSONDecoder().decode([AppTimer].self, from: Data(raw.utf8))) ?? [] }
    static func encode(_ t: [AppTimer]) -> String { (try? JSONEncoder().encode(t)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
}

/// The app's own chat account on Kick and Twitch (see CONTEXT.md): scene notices, viewer commands, timers and thank-yous.
/// Never posts as the streamer. One paced queue per platform, and everything only while live.
/// ponytail: settings are plain UserDefaults keys (bool switches default on, templates fall back to `defaults`).
@MainActor
final class AppBot: ObservableObject {
    static let shared = AppBot()

    /// Set once from the App; nothing runs before that.
    var streamer: Streamer?
    var platforms: Platforms?

    /// Last connect / send problem, shown in Settings › App bot.
    @Published var status = ""
    @Published var twitchBotName = UserDefaults.standard.string(forKey: "botTwitchName") ?? ""

    private let store: TokenStore = UserDefaults.standard
    private var queue: [String: [String]] = [:]       // origin -> messages waiting for their turn
    private var draining: Set<String> = []
    private var sent: [String] = []                   // our last texts: chat echoes them back, they are not viewers
    private var answered: [String: Date] = [:]        // "origin|!cmd" -> last answer
    private var msgs: [String: Int] = [:]             // origin -> viewer messages so far this stream
    private var marks: [String: (at: Date, msgs: Int)] = [:]   // "timer|origin" -> state at its last post
    private var lastTimer: [String: Date] = [:]       // origin -> last timer post
    private var holdingGPS = false

    static let defaults = [
        "botTplBrbOn": "Connection's weak, back in a moment", "botTplBrbOff": "We're back!",
        "botTplStartingOn": "Starting soon!", "botTplEndingOn": "Thanks for watching!",
        "botTplFollow": "{user}, thanks for the follow!", "botTplSub": "{user}, thanks for subscribing!",
        "botTplGift": "{user}, thanks for the {count} gifted subs!", "botTplRaid": "{user}, thanks for the raid with {count} viewers!",
    ]
    private static let commands = ["!location", "!speed", "!distance", "!weather", "!battery", "!uptime", "!commands"]

    private func flag(_ key: String, _ fallback: Bool = true) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }

    /// Live, or test mode (Settings › App bot): answers, notices and thank-yous work offline too. Timers stay live-only.
    private var active: Bool { streamer?.live == true || flag("botTestMode", false) }
    private func tpl(_ key: String) -> String { UserDefaults.standard.string(forKey: key) ?? Self.defaults[key] ?? "" }

    // MARK: pure decisions -- see demo()

    /// Same command on the same platform: once per 30 s, unless a mod or the broadcaster typed it.
    static func cooldownOK(last: Date?, now: Date, privileged: Bool) -> Bool {
        privileged || last.map { now.timeIntervalSince($0) >= 30 } ?? true
    }

    /// Interval passed (never under 5 min), 5 viewer messages since its last post, and 5 min since any timer posted there.
    static func timerDue(since: Date, minutes: Int, msgs: Int, lastAny: Date?, now: Date) -> Bool {
        now.timeIntervalSince(since) >= Double(max(minutes, 5) * 60) && msgs >= 5
            && lastAny.map { now.timeIntervalSince($0) >= 300 } ?? true
    }

    static func fill(_ template: String, user: String, count: Int) -> String {
        template.replacingOccurrences(of: "{user}", with: user).replacingOccurrences(of: "{count}", with: String(count))
    }

    // MARK: sending

    private func platformOn(_ origin: String) -> Bool {
        guard let p = platforms else { return false }
        if origin == "kick" { return flag("botKick", false) && p.kickConnected }
        return origin == "twitch" && flag("botTwitch", false) && !p.twitchUserID.isEmpty
            && store.string(forKey: "twitchBotAccess") != nil && UserDefaults.standard.string(forKey: "botTwitchID") != nil
    }

    /// Queues `text` for `origin`: one message per 1.5 s per platform (Twitch allows 20 per 30 s to a non-mod), delayed, never dropped.
    private func say(_ origin: String, _ text: String) {
        guard active, platformOn(origin), !text.isEmpty else { return }
        queue[origin, default: []].append(String(text.prefix(500)))   // Kick's limit
        guard draining.insert(origin).inserted else { return }
        Task {
            while let t = queue[origin]?.first {
                queue[origin]?.removeFirst()
                await post(origin, t)
                try? await Task.sleep(for: .seconds(1.5))
            }
            draining.remove(origin)
        }
    }

    private func post(_ origin: String, _ text: String) async {
        guard let p = platforms else { return }
        sent.append(text); if sent.count > 20 { sent.removeFirst() }
        do {
            if origin == "kick" {
                // type "bot" posts as the app's bot account of the token owner's channel; never fall back to "user".
                _ = try await p.kick.api().call("POST", "/public/v1/chat", body: ["content": text, "type": "bot"])
            } else {
                _ = try await twitchAPI().call("POST", "/chat/messages", body: [
                    "broadcaster_id": p.twitchUserID, "sender_id": UserDefaults.standard.string(forKey: "botTwitchID") ?? "", "message": text])
            }
        } catch {
            applog("chat", "app bot \(origin) send failed: \(error.localizedDescription)", error: true)
            status = "\(origin == "kick" ? "Kick" : "Twitch"): \(error.localizedDescription)"
        }
    }

    // MARK: Twitch app bot account (second account, tokens under the "twitchBot" prefix)

    private func twitchAPI() -> PlatformEndpoint {
        PlatformEndpoint(base: "https://api.twitch.tv/helix", tokenKey: "twitchBotAccess",
            headers: ["Client-Id": PlatformConfig.twitchID], store: store) {
            let json = try await PlatformNet.form("https://id.twitch.tv/oauth2/token", [
                "grant_type": "refresh_token", "client_id": PlatformConfig.twitchID, "refresh_token": self.store.string(forKey: "twitchBotRefresh") ?? ""])
            try self.store.saveTokens(json, prefix: "twitchBot")
        }
    }

    /// Device-code login like TwitchService.connect. The device flow has no account picker, so the account is whichever
    /// one is signed in on the activate page (use a private tab or log out first).
    func connectTwitch() {
        Task {
            do {
                let scopes = "user:read:chat user:write:chat user:bot"
                let dev = try await PlatformNet.form("https://id.twitch.tv/oauth2/device", ["client_id": PlatformConfig.twitchID, "scopes": scopes])
                guard let deviceCode = dev["device_code"] as? String else { throw PlatformNet.err("no device_code: \(dev)") }
                let url = dev["verification_uri"] as? String ?? "https://www.twitch.tv/activate"
                status = "Enter code \(dev["user_code"] as? String ?? "") on Twitch as the bot account"
                if let u = URL(string: url) { await UIApplication.shared.open(u) }
                let interval = max(dev["interval"] as? Int ?? 5, 5)
                for _ in 0..<(900 / interval) {                        // ponytail: 15 min ceiling
                    try await Task.sleep(for: .seconds(interval))
                    let r = try await PlatformNet.form("https://id.twitch.tv/oauth2/token", [
                        "client_id": PlatformConfig.twitchID, "scopes": scopes, "device_code": deviceCode,
                        "grant_type": "urn:ietf:params:oauth:grant-type:device_code"], allowError: true)
                    if r["access_token"] != nil {
                        try store.saveTokens(r, prefix: "twitchBot")
                        let u = ((try await twitchAPI().call("GET", "/users"))["data"] as? [[String: Any]])?.first
                        UserDefaults.standard.set(u?["id"] as? String, forKey: "botTwitchID")
                        twitchBotName = u?["display_name"] as? String ?? ""
                        UserDefaults.standard.set(twitchBotName, forKey: "botTwitchName")
                        status = "Twitch bot connected as \(twitchBotName)"
                        return
                    }
                    if (r["message"] as? String) != "authorization_pending" { throw PlatformNet.err("Twitch: \(r["message"] ?? r)") }
                }
                status = "Twitch login timed out"
            } catch { status = error.localizedDescription }
        }
    }

    func disconnectTwitch() {
        store.forget("twitchBot")
        ["botTwitchID", "botTwitchName"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        twitchBotName = ""
    }

    // MARK: hooks

    /// From Streamer.sceneRole: BRB on/off, Starting, Ending. An empty template posts nothing.
    func role(_ role: String, on: Bool) {
        guard flag("botNotices") else { return }
        let text = tpl("botTpl" + role.capitalized + (on ? "On" : "Off"))
        ["kick", "twitch"].forEach { say($0, text) }
    }

    /// From the chat.events loop: viewer commands, the timers' message count and thank-yous.
    func handle(_ e: ChatEvent) {
        guard !e.flagged, active, e.origin == "kick" || e.origin == "twitch" else { return }
        switch e.kind {
        case .message: message(e)
        case .follow: thank(e, "botTplFollow")
        case .subscribe: thank(e, e.count > 0 ? "botTplGift" : "botTplSub")
        case .raid: thank(e, "botTplRaid")
        default: break
        }
    }

    private func thank(_ e: ChatEvent, _ key: String) {
        guard flag("botThanks"), !Speaker.isBlocked(e.user, extra: UserDefaults.standard.string(forKey: "ttsBlocked") ?? "") else { return }
        say(e.origin, Self.fill(tpl(key), user: e.user, count: e.count))
    }

    private func message(_ e: ChatEvent) {
        if sent.contains(e.text) || (e.origin == "twitch" && !twitchBotName.isEmpty && e.user.caseInsensitiveCompare(twitchBotName) == .orderedSame) { return }
        if !BotList.isBot(e.user) { msgs[e.origin, default: 0] += 1 }
        let cmd = e.text.split(whereSeparator: \.isWhitespace).first?.lowercased() ?? ""
        let key = e.origin + "|" + cmd
        guard Self.commands.contains(cmd) else { return }
        guard platformOn(e.origin), flag("botCmd" + cmd.dropFirst().capitalized) else {
            applog("bot", "\(cmd) on \(e.origin) ignored: \(platformOn(e.origin) ? "command switched off" : "app bot off or not connected there")")
            return
        }
        let now = Date()
        let privileged = !Set(e.badges).isDisjoint(with: ["broadcaster", "moderator"])
        // Offline (test mode) only the streamer and mods get answers: !location to anyone off-stream would say where you are.
        guard streamer?.live == true || privileged else { applog("bot", "\(cmd) from \(e.user) ignored: offline, not you or a mod"); return }
        guard Self.cooldownOK(last: answered[key], now: now, privileged: privileged) else { applog("bot", "\(cmd) ignored: cooldown"); return }
        answered[key] = now
        let name = (e.origin == "kick" ? platforms?.kickUser : platforms?.twitchUser) ?? ""
        if let a = answer(cmd, name.isEmpty ? "The streamer" : name) { say(e.origin, a) } else { applog("bot", "\(cmd): value not known yet, staying silent") }
    }

    /// Offline (test mode) the health monitor isn't tracking the battery: read it directly. Monitoring stays on until the
    /// health monitor next turns it off at the end of a live session.
    private static func batteryNow() -> Int? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : Int(level * 100)
    }

    /// nil (stay silent) when the value is not known yet.
    private func answer(_ cmd: String, _ name: String) -> String? {
        let loc = WidgetLocation.shared
        func known(_ s: String) -> String? { s == "--" ? nil : s }
        switch cmd {
        case "!location":
            if flag("botHideLocation", false) { return "Location is private right now" }
            return loc.regionText.map { "\(name) is in \($0)" }
        case "!speed": return known(loc.speedText).map { "\(name) is going \($0)" }
        case "!distance": return "\(name) has travelled \(loc.distanceText(since: streamer?.liveSince)) this stream"
        case "!weather": return known(WidgetWeather.shared.plainText).map { "It's \($0) where \(name) is" }
        case "!commands":   // whichever commands are switched on right now
            let on = Self.commands.filter { $0 != "!commands" && flag("botCmd" + $0.dropFirst().capitalized) }
            return on.isEmpty ? nil : "Commands: " + on.joined(separator: " ")
        case "!battery": return (streamer?.phoneBattery ?? Self.batteryNow()).map { "\(name)'s phone is at \($0)%" }
        case "!uptime":
            guard let since = streamer?.liveSince else { return nil }
            let m = max(0, Int(Date().timeIntervalSince(since))) / 60
            return "\(name) has been live for \(m >= 60 ? "\(m / 60) h " : "")\(m % 60) min"
        default: return nil
        }
    }

    /// From Streamer's 1 s tick: keeps the GPS on while location commands are possible, runs the timers.
    func tick() {
        let live = streamer?.live == true
        let wantGPS = active && (platformOn("kick") || platformOn("twitch"))
            && ["botCmdLocation", "botCmdSpeed", "botCmdDistance", "botCmdWeather"].contains { flag($0) }
        if wantGPS != holdingGPS {
            holdingGPS = wantGPS
            if wantGPS { WidgetLocation.shared.retain() } else { WidgetLocation.shared.release() }
        }
        if wantGPS, flag("botCmdWeather") { _ = WidgetWeather.shared.plainText }   // reading it is what turns the fetch on
        guard live else { msgs = [:]; marks = [:]; lastTimer = [:]; return }
        guard flag("botTimersOn", false), streamer?.roleActive != "brb" else { return }
        let now = Date()
        for t in AppTimer.decode(UserDefaults.standard.string(forKey: "botTimers") ?? "[]") where !t.text.isEmpty {
            for o in ["kick", "twitch"] where platformOn(o) {
                let k = "\(t.id)|\(o)", m = msgs[o, default: 0]
                guard let mark = marks[k] else { marks[k] = (now, m); continue }
                if Self.timerDue(since: mark.at, minutes: t.minutes, msgs: m - mark.msgs, lastAny: lastTimer[o], now: now) {
                    marks[k] = (now, m); lastTimer[o] = now
                    say(o, t.text)
                }
            }
        }
    }

    #if DEBUG
    static func demo() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        assert(cooldownOK(last: nil, now: t, privileged: false))
        assert(!cooldownOK(last: t, now: t.addingTimeInterval(29), privileged: false))
        assert(cooldownOK(last: t, now: t.addingTimeInterval(30), privileged: false))
        assert(cooldownOK(last: t, now: t.addingTimeInterval(1), privileged: true))
        let later = t.addingTimeInterval(600)
        assert(timerDue(since: t, minutes: 10, msgs: 5, lastAny: nil, now: later))
        assert(!timerDue(since: t, minutes: 10, msgs: 4, lastAny: nil, now: later))          // too quiet
        assert(!timerDue(since: t, minutes: 11, msgs: 9, lastAny: nil, now: later))          // too early
        assert(!timerDue(since: t, minutes: 1, msgs: 9, lastAny: nil, now: t.addingTimeInterval(120)))   // minutes floor at 5
        assert(!timerDue(since: t, minutes: 10, msgs: 9, lastAny: later.addingTimeInterval(-299), now: later))   // another timer just posted
        assert(timerDue(since: t, minutes: 10, msgs: 9, lastAny: later.addingTimeInterval(-300), now: later))
        assert(fill("{user}: {count} subs", user: "bob", count: 5) == "bob: 5 subs")
        applog("chat", "AppBot.demo() passed")
    }
    #endif
}
