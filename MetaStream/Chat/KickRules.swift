import Foundation

/// Data-driven Kick alerts: Kick's non-chat Pusher events are undocumented and get renamed, so which
/// events mean what lives in a JSON rules table (built-in default, overridable from metastream.iamsaeed.dev).
/// The same JSON is committed as docs/kick-events.json and embedded by the Android app.
enum KickRules {
    struct Rule: Sendable {
        let kind: ChatEvent.Kind
        var user: [String] = [], text: [String] = [], count: [String] = [], amount: [String] = []
        var minCount = 0
        var require: String?
    }

    struct Rules: Sendable {
        var channels: [String] = []
        var events: [String: Rule] = [:]
    }

    static let defaultJSON = #"""
    {
      "version": 1,
      "channels": ["chatrooms.{chatroomId}.v2", "channel.{channelId}"],
      "events": {
        "App\\Events\\SubscriptionEvent": {"kind": "subscribe", "user": ["username"]},
        "App\\Events\\GiftedSubscriptionsEvent": {"kind": "subscribe", "user": ["gifter_username", "username"], "count": ["gifted_usernames", "quantity", "gifter_total"], "minCount": 1},
        "App\\Events\\StreamHostEvent": {"kind": "raid", "user": ["host_username"], "count": ["number_viewers"]},
        "App\\Events\\FollowersUpdated": {"kind": "follow", "user": ["username"], "require": "followed"},
        "App\\Events\\KicksGifted": {"kind": "tip", "user": ["sender.username", "username"], "amount": ["gift.amount", "amount"], "text": ["message"]}
      }
    }
    """#

    static let defaults = decode(Data(defaultJSON.utf8)) ?? Rules()

    private static let remoteURL = URL(string: "https://metastream.iamsaeed.dev/kick-events.json")!
    private static var cacheURL: URL? { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("kick-events.json") }

    /// Remote (cached on success) -> cached -> built-in. Never throws.
    static func load() async -> (rules: Rules, source: String) {
        var req = URLRequest(url: remoteURL)
        req.timeoutInterval = 5
        if let data = try? await URLSession.shared.data(for: req).0, let rules = decode(data) {
            if let cacheURL { try? data.write(to: cacheURL) }
            return (rules, "remote")
        }
        if let cacheURL, let data = try? Data(contentsOf: cacheURL), let rules = decode(data) { return (rules, "cached") }
        return (defaults, "built-in")
    }

    /// nil unless the JSON is an object with version 1; malformed individual rules are skipped.
    static func decode(_ data: Data) -> Rules? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], chatInt(root["version"]) == 1 else { return nil }
        var rules = Rules(channels: (root["channels"] as? [Any])?.compactMap { $0 as? String } ?? [])
        for (name, raw) in root["events"] as? [String: Any] ?? [:] {
            guard let o = raw as? [String: Any], let kind = kind(o["kind"] as? String) else { continue }
            func paths(_ key: String) -> [String] { (o[key] as? [Any])?.compactMap { $0 as? String } ?? [] }
            rules.events[name] = Rule(kind: kind, user: paths("user"), text: paths("text"), count: paths("count"), amount: paths("amount"),
                                      minCount: chatInt(o["minCount"]) ?? 0, require: o["require"] as? String)
        }
        return rules
    }

    private static func kind(_ s: String?) -> ChatEvent.Kind? {
        switch s {
        case "follow": return .follow
        case "subscribe": return .subscribe
        case "raid": return .raid
        case "tip": return .tip
        case "cheer": return .cheer
        default: return nil
        }
    }

    /// Channel names to subscribe to; a template with an unknown or unavailable placeholder is skipped.
    static func channels(_ rules: Rules, chatroomID: Int, channelID: Int?) -> [String] {
        rules.channels.compactMap { template in
            var name = template.replacingOccurrences(of: "{chatroomId}", with: String(chatroomID))
            if let channelID { name = name.replacingOccurrences(of: "{channelId}", with: String(channelID)) }
            return name.contains("{") ? nil : name
        }
    }

    /// Pure: nil when the event has no rule, the data isn't a JSON object, `require` fails, or the user is empty.
    static func parse(_ rules: Rules, event: String, data: String?) -> ChatEvent? {
        guard let rule = rules.events[event], let data,
              let obj = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any]
        else { return nil }
        if let req = rule.require, !truthy(resolve(obj, req)) { return nil }
        let user = string(obj, rule.user)
        guard !user.isEmpty else { return nil }
        let text = string(obj, rule.text)
        if rule.kind == .tip { return ChatEvent(kind: .tip, user: user, text: text, amountCents: number(obj, rule.amount), origin: "kick") }
        return ChatEvent(kind: rule.kind, user: user, text: text, count: max(number(obj, rule.count), rule.minCount), origin: "kick")
    }

    /// First dot path that resolves to a non-null, non-empty value.
    private static func resolve(_ obj: [String: Any], _ path: String) -> Any? {
        var cur: Any? = obj
        for key in path.split(separator: ".") { cur = (cur as? [String: Any])?[String(key)] }
        if cur is NSNull { return nil }
        if let s = cur as? String, s.isEmpty { return nil }
        if let a = cur as? [Any], a.isEmpty { return nil }
        return cur
    }

    private static func string(_ obj: [String: Any], _ paths: [String]) -> String {
        for p in paths {
            let v = resolve(obj, p)
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
        }
        return ""
    }

    private static func number(_ obj: [String: Any], _ paths: [String]) -> Int {
        for p in paths {
            let v = resolve(obj, p)
            if let a = v as? [Any] { return a.count }
            if let n = chatInt(v) { return n }
        }
        return 0
    }

    private static func truthy(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let s = v as? String { return s == "true" }
        return (v as? Int) == 1
    }
}
