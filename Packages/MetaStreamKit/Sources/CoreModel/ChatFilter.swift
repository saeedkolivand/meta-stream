import Foundation

/// Chat text rules shared by read-aloud, the stream widgets, moderation and the bot (Android: chat ChatFilter.kt and
/// Sanitize.kt): what is never said or shown, what read-aloud skips, and the cleanup before speaking or summarizing.
public enum ChatFilter {
    // ponytail: the slurs and self-harm phrases most often behind hateful-conduct bans; `blocked` adds any language.
    public static let bannedTerms = ["nigger", "nigga", "faggot", "fag", "retard", "tranny", "kike", "chink", "spic",
                                     "wetback", "gook", "kys", "kill yourself", "heil hitler"]
    private static let squashedBanned = bannedTerms.map(squash)   // the widgets check every row many times a second
    private static let leet: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
                                                       "@": "a", "$": "s", "!": "i", "|": "i"]

    /// Lowercased letters only, leetspeak undone and repeats collapsed: "N1iiGG3R" -> "niger".
    public static func squash(_ text: String) -> String {
        var out = ""
        for raw in text.lowercased().folding(options: .diacriticInsensitive, locale: nil) {
            let char = leet[raw] ?? raw
            if char.isLetter, out.last != char { out.append(char) }
        }
        return out
    }

    /// True if `text` holds a banned term or one of `extra` (comma separated), through leetspeak and stretched letters;
    /// terms of 5+ letters also through spacing ("n i g g e r"). Shorter ones match whole words only, so "spicy" passes.
    /// ponytail: errs toward silence; a skipped harmless message costs nothing, a spoken slur can cost the channel.
    public static func isBlocked(_ text: String, extra: String) -> Bool {
        let terms = squashedBanned + extra.split(separator: ",").map { squash(String($0)) }.filter { !$0.isEmpty }
        let words = text.split { !$0.isLetter && leet[$0] == nil }.map { squash(String($0)) }
        let joined = squash(text)
        return terms.contains { term in
            term.count >= 5 ? joined.contains(term) : words.contains { $0 == term || $0 == term + "s" }
        }
    }

    /// !commands and names in `ignored`. Bots are decided separately (BotList + botReadMode).
    public static func isNoise(user: String, text: String, ignored: String) -> Bool {
        let name = user.lowercased()
        let names = ignored.lowercased().split { $0 == "," || $0.isWhitespace }
            .map { $0.hasPrefix("@") ? String($0.dropFirst()) : String($0) }
        // Skip spaces, line breaks and invisible format characters (zero-width space, BOM) before the "!".
        let start = text.unicodeScalars.drop { $0.properties.isWhitespace || $0.properties.generalCategory == .format }
        return names.contains(name) || start.first == "!"
    }

    /// Strips URLs/emotes/@ (keeping the name), collapses whitespace, caps length so one troll can't hog the queue.
    public static func sanitize(_ raw: String, maxLength: Int = 200) -> String {
        var text = raw
        for pattern in [SharedPatterns.url, SharedPatterns.kickEmote, SharedPatterns.colonEmote] {
            text = pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = SharedPatterns.mention.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                               withTemplate: "$1")
        text = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return text.count > maxLength ? String(text.prefix(maxLength)) : text
    }
}

extension ChatEvent {
    /// A slur or blocked word (Settings → Read aloud) in the name or text, or flagged by AI moderation:
    /// never read aloud and kept off the stream widgets.
    public var offensive: Bool {
        if flagged { return true }
        let extra = UserDefaults.standard.string(forKey: "ttsBlocked") ?? ""
        return ChatFilter.isBlocked(user, extra: extra) || ChatFilter.isBlocked(text, extra: extra)
    }
}
