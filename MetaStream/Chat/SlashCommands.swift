import Foundation

/// Slash commands typed in the chat input (see CONTEXT.md): parsed here, carried out through the platform's
/// own moderation API by `SlashRunner`, never posted as a message.
enum SlashCommand {
    static func parse(_ text: String) -> (name: String, args: [String])? {
        guard text.hasPrefix("/") else { return nil }
        let parts = text.dropFirst().split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = parts.first else { return nil }
        return (name.lowercased(), Array(parts.dropFirst()))
    }

    /// "600" -> 600, "10m" -> 600, "1h", "1d", "30s". nil when it isn't a duration (so the word is part of a reason).
    static func seconds(_ s: String) -> Int? {
        var n = s.lowercased(), mult = 1
        if let m = ["s": 1, "m": 60, "h": 3600, "d": 86400][String(n.suffix(1))] { mult = m; n.removeLast() }
        guard let v = Int(n), v > 0, v <= 1_000_000 else { return nil }
        return v * mult
    }

    static func pretty(_ s: Int) -> String {
        s % 86400 == 0 ? "\(s / 86400) d" : s % 3600 == 0 ? "\(s / 3600) h" : s % 60 == 0 ? "\(s / 60) min" : "\(s) s"
    }

    #if DEBUG
    static func demo() {
        let ban = parse("/ban bob spam")
        assert(ban?.name == "ban" && ban?.args == ["bob", "spam"])
        assert(parse("/CLEAR")?.name == "clear" && parse("/CLEAR")?.args == [])
        assert(parse("hello") == nil && parse("/") == nil && parse("/  ") == nil)
        assert(seconds("600") == 600 && seconds("10m") == 600 && seconds("1h") == 3600 && seconds("1d") == 86400)
        assert(seconds("spam") == nil && seconds("0") == nil && seconds("m") == nil)
        assert(pretty(600) == "10 min" && pretty(86400) == "1 d")
        applog("chat", "SlashCommand.demo() passed")
    }
    #endif
}

/// Runs one parsed slash command against `origin`; returns the one-line note shown to the streamer.
@MainActor
struct SlashRunner {
    let p: Platforms
    let chat: ChatFeed
    let origin: String
    private var isKick: Bool { origin == "kick" }

    private static let both = ["ban", "unban", "timeout", "untimeout", "delete", "clear", "title", "category", "ad", "help"]
    private static let twitchOnly = ["slow", "emoteonly", "followers", "subscribers", "raid", "announce", "marker", "clip"]
    private static let kickLater = ["host", "poll", "prediction"]

    func run(_ name: String, _ a: [String]) async -> String {
        let label = DisplayNames.platformName(origin)
        if name == "help" { return "\(label): " + (Self.both + (isKick ? [] : Self.twitchOnly)).map { "/" + $0 }.joined(separator: " ") }
        guard (Self.both + Self.twitchOnly + Self.kickLater).contains(name) else { return "Unknown command /\(name)" }
        if isKick, Self.kickLater.contains(name) { return "/\(name) is coming with the kick.com session" }  // adr/0005
        if isKick, Self.twitchOnly.contains(name) { return "Kick has no API for /\(name) yet" }
        if !isKick, Self.kickLater.contains(name) { return "Twitch has no /\(name)" }
        if isKick ? p.kickUserID == 0 : p.twitchUserID.isEmpty { return "\(label) isn't connected" }
        if !isKick, let f = Self.feature(name), !p.twitchHasScopes(TwitchService.actionScopes[f] ?? []) { return "Reconnect Twitch to allow \(f)" }
        do {
            switch name {
            case "ban", "timeout", "unban", "untimeout": return try await banning(name, a)
            case "delete":
                guard let raw = a.first else { return "Usage: /delete user" }
                guard let m = lastMessage(from: login(raw)) else { return "No recent message from \(login(raw))" }
                try await deleteMessage(m.id)
                return "Deleted the last message from \(m.user)"
            case "clear": return try await clearChat()
            case "slow", "emoteonly", "followers", "subscribers": return try await chatMode(name, a)
            case "title":
                let t = a.joined(separator: " ")
                guard !t.isEmpty else { return "Usage: /title text" }
                if isKick { await p.kickApply(title: t, category: nil, tags: p.kickTags) }
                else { await p.twitchApply(title: t, category: nil, tags: p.twitchTags, delay: p.twitchDelay) }
                return (isKick ? p.kickTitle : p.twitchTitle) == t ? "Title set" : p.status
            case "category":
                let q = a.joined(separator: " ")
                guard !q.isEmpty else { return "Usage: /category name" }
                let found: [StreamCategory]
                if isKick { found = await p.kickSearch(q) } else { found = await p.twitchSearch(q) }
                guard let c = found.first else { return "No category matching \(q)" }
                if isKick { await p.kickApply(title: p.kickTitle, category: c, tags: p.kickTags) }
                else { await p.twitchApply(title: p.twitchTitle, category: c, tags: p.twitchTags, delay: p.twitchDelay) }
                return (isKick ? p.kickCategory : p.twitchCategory)?.id == c.id ? "Category set to \(c.name)" : p.status
            case "ad":
                let s = a.first.flatMap(Int.init) ?? (isKick ? 30 : 90)
                if isKick {
                    _ = try await p.kick.api().call("POST", "/public/v1/ads/ad-break", body: ["break_duration_seconds": min(max(s, 7), 90), "id": UUID().uuidString])
                    return "Ad break started"
                }
                await p.twitchStartCommercial(seconds: min(max((s + 15) / 30 * 30, 30), 180))  // Twitch only takes 30...180 in steps of 30
                return p.status
            case "raid":
                guard let c = a.first else { return "Usage: /raid channel" }
                await p.twitchRaid(c)
                return p.status
            case "announce":
                guard !a.isEmpty else { return "Usage: /announce text" }
                await p.twitchAnnounce(a.joined(separator: " "))
                return p.status
            case "marker":
                try await p.twitchCreateMarker()
                return "Marker added"
            default:   // "clip"
                return "Clip: \(try await p.twitchCreateClip().url)"
            }
        } catch { return error.localizedDescription }
    }

    /// Twitch scope feature (TwitchService.actionScopes key) each command needs.
    private static func feature(_ name: String) -> String? {
        switch name {
        case "ban", "unban", "timeout", "untimeout", "delete", "clear": return "moderation"
        case "slow", "emoteonly", "followers", "subscribers": return "chat lockdown"
        case "announce": return "announcements"
        case "raid": return "raids"
        case "ad": return "commercial"
        case "clip": return "clips"
        default: return nil
        }
    }

    private func login(_ raw: String) -> String { raw.hasPrefix("@") ? String(raw.dropFirst()).lowercased() : raw.lowercased() }

    // ponytail: only the ChatFeed buffer (last 100 events, all origins) is searched, no separate id store.
    private func lastMessage(from login: String) -> ChatEvent? {
        chat.recent.last { $0.origin == origin && $0.kind == .message && $0.user.lowercased() == login && !$0.id.isEmpty }
    }

    private var mod: [URLQueryItem] { [.init(name: "broadcaster_id", value: p.twitchUserID), .init(name: "moderator_id", value: p.twitchUserID)] }

    /// Platform user id: from recent chat, else looked up by login (a Kick username is its channel slug).
    private func userID(_ login: String) async throws -> String? {
        if let e = chat.recent.last(where: { $0.origin == origin && $0.kind == .message && $0.user.lowercased() == login && !$0.userId.isEmpty }) { return e.userId }
        if isKick {
            // ponytail: unverified whether Kick slugs keep "_" or turn it into "-"; try as typed, then hyphenated.
            for slug in Set([login, login.replacingOccurrences(of: "_", with: "-")]) {
                let r = try await p.kick.api().call("GET", "/public/v1/channels", query: [.init(name: "slug", value: slug)])
                if let id = (r["data"] as? [[String: Any]])?.first?["broadcaster_user_id"] as? Int { return String(id) }
            }
            return nil
        }
        let r = try await p.twitch.api().call("GET", "/users", query: [.init(name: "login", value: login)])
        return (r["data"] as? [[String: Any]])?.first?["id"] as? String
    }

    private func banning(_ name: String, _ a: [String]) async throws -> String {
        guard let raw = a.first else { return "Usage: /\(name) user" }
        let who = login(raw)
        guard let uid = try await userID(who) else { return "Can't find \(who)" }
        if name.hasPrefix("un") {
            if isKick { _ = try await p.kick.api().call("DELETE", "/public/v1/moderation/bans", body: ["broadcaster_user_id": p.kickUserID, "user_id": Int(uid) ?? 0]) }
            else { _ = try await p.twitch.api().call("DELETE", "/moderation/bans", query: mod + [.init(name: "user_id", value: uid)]) }
            return "Unbanned \(who)"
        }
        var rest = Array(a.dropFirst()), secs: Int?
        if name == "timeout" {
            secs = rest.first.flatMap(SlashCommand.seconds)
            if secs != nil { rest.removeFirst() }
            // Kick wants whole minutes 1...10080, Twitch seconds up to 2 weeks.
            secs = isKick ? min(max(((secs ?? 600) + 59) / 60, 1), 10080) * 60 : min(secs ?? 600, 1_209_600)
        }
        let reason = String(rest.joined(separator: " ").prefix(100))
        if isKick {
            var body: [String: Any] = ["broadcaster_user_id": p.kickUserID, "user_id": Int(uid) ?? 0]
            if let secs { body["duration"] = secs / 60 }
            if !reason.isEmpty { body["reason"] = reason }
            _ = try await p.kick.api().call("POST", "/public/v1/moderation/bans", body: body)
        } else {
            var data: [String: Any] = ["user_id": uid, "reason": reason]
            if let secs { data["duration"] = secs }
            _ = try await p.twitch.api().call("POST", "/moderation/bans", query: mod, body: ["data": data])
        }
        return secs.map { "Timed out \(who) for \(SlashCommand.pretty($0))" } ?? "Banned \(who)"
    }

    private func deleteMessage(_ id: String) async throws {
        if isKick { _ = try await p.kick.api().call("DELETE", "/public/v1/chat/\(id)") }
        else { _ = try await p.twitch.api().call("DELETE", "/moderation/chat", query: mod + [.init(name: "message_id", value: id)]) }
    }

    private func clearChat() async throws -> String {
        if !isKick {
            _ = try await p.twitch.api().call("DELETE", "/moderation/chat", query: mod)
            return "Chat cleared"
        }
        // ponytail: Kick has no clear endpoint, so delete the Kick messages still in the feed buffer one by one;
        // a later step does a real clear through the kick.com session.
        let ids = chat.recent.filter { $0.origin == "kick" && $0.kind == .message && !$0.id.isEmpty }.map(\.id)
        var n = 0
        for id in ids {
            do { try await deleteMessage(id); n += 1 }
            catch where error.localizedDescription.contains("HTTP 429") { return "Rate limited: deleted \(n) of \(ids.count) messages" }
            catch { continue }   // already gone
        }
        return "Deleted \(n) recent messages"
    }

    private func chatMode(_ name: String, _ a: [String]) async throws -> String {
        let off = a.first?.lowercased() == "off", n = a.first.flatMap(Int.init)
        let body: [String: Any]
        let note: String
        switch name {
        case "slow":
            let s = min(max(n ?? 30, 3), 120)
            body = off ? ["slow_mode": false] : ["slow_mode": true, "slow_mode_wait_time": s]
            note = off ? "Slow mode off" : "Slow mode \(s) s"
        case "emoteonly":
            body = ["emote_mode": !off]
            note = off ? "Emote-only off" : "Emote-only on"
        case "followers":
            let m = min(max(n ?? 0, 0), 129_600)
            body = off ? ["follower_mode": false] : ["follower_mode": true, "follower_mode_duration": m]
            note = off ? "Followers-only off" : "Followers-only \(m) min"
        default:
            body = ["subscriber_mode": !off]
            note = off ? "Subscribers-only off" : "Subscribers-only on"
        }
        _ = try await p.twitch.api().call("PATCH", "/chat/settings", query: mod, body: body)
        return note
    }
}
