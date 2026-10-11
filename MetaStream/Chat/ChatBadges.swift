import Foundation

/// Pure parsing for chat role badges + username colors, kept free of SwiftUI so tests can hit it directly.
/// Badges are normalized to a fixed vocabulary; anything unknown is dropped.
/// ponytail: chips are SF Symbols, not the platforms' own badge art. Twitch badge images need Helix
/// (`/chat/badges` + `/chat/badges/global`) - upgrade there if per-channel sub-tier art is wanted.
enum ChatBadges {
    /// Display order, most important first.
    static let order = ["broadcaster", "moderator", "staff", "vip", "verified", "founder", "subscriber", "og"]

    /// Maps a platform badge id (Twitch set_id / Kick type) to our vocabulary, nil if unknown.
    static func normalize(_ raw: String) -> String? {
        switch raw.lowercased() {
        case "broadcaster": return "broadcaster"
        case "moderator": return "moderator"
        case "vip": return "vip"
        case "subscriber": return "subscriber"
        case "founder": return "founder"
        case "verified", "partner": return "verified"
        case "og": return "og"
        case "staff", "admin", "global_mod": return "staff"
        default: return nil
        }
    }

    /// Normalizes, dedupes and sorts raw ids into display order.
    static func normalized(_ raws: [String]) -> [String] {
        let known = Set(raws.compactMap(normalize))
        return order.filter(known.contains)
    }

    /// Twitch EventSub `badges: [{set_id, id, info}]`.
    static func twitch(_ badges: Any?) -> [String] {
        normalized((badges as? [[String: Any]] ?? []).compactMap { $0["set_id"] as? String })
    }

    /// Kick `sender.identity.badges: [{type, text}]`.
    static func kick(_ identity: [String: Any]?) -> [String] {
        normalized((identity?["badges"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String })
    }

    /// YouTube `authorDetails` booleans.
    static func youtube(_ author: [String: Any]) -> [String] {
        var raw: [String] = []
        if author["isChatOwner"] as? Bool == true { raw.append("broadcaster") }
        if author["isChatModerator"] as? Bool == true { raw.append("moderator") }
        if author["isChatSponsor"] as? Bool == true { raw.append("subscriber") }
        if author["isVerified"] as? Bool == true { raw.append("verified") }
        return normalized(raw)
    }

    /// Accepts "#RRGGBB" (case-insensitive) and returns it uppercased; anything else (empty, short, junk) is nil.
    static func color(_ raw: Any?) -> String? {
        guard let s = raw as? String, s.count == 7, s.hasPrefix("#"),
              UInt32(s.dropFirst(), radix: 16) != nil else { return nil }
        return s.uppercased()
    }

    /// RGB (0...1) of `hex`, mixed toward white until its luminance reaches `minLuminance`, so dark user
    /// colors (Twitch's default #0000FF etc.) stay legible on black. Mixing t toward white raises luminance
    /// Y to Y + (1 - Y) * t, so t has a closed form.
    static func readableRGB(hex: String, minLuminance: Double = 0.5) -> (r: Double, g: Double, b: Double)? {
        guard let v = color(hex).flatMap({ UInt32($0.dropFirst(), radix: 16) }) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard y < minLuminance else { return (r, g, b) }
        let t = (minLuminance - y) / (1 - y)
        return (r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t)
    }
}
