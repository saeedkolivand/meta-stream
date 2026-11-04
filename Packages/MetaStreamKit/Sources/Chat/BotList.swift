// Which chat accounts are bots and what a bot line means (iOS keeps this in Chat: the on-stream chat widget, the chat
// sheet and read-aloud all ask it; Android: bot BotList).
import CoreLogging
import Foundation

/// The shared bot list (AppStorage "botNames", comma separated) and what a bot message means for the streamer.
public enum BotList {
    public static let defaultNames = "nightbot,streamelements,streamlabs,moobot,fossabot,botrix,botrixoficial,kicklet,sery_bot,wizebot,soundalerts"
    public static let defaultTriggers = "won, winner"

    private static func stored(_ key: String, _ fallback: String) -> String { UserDefaults.standard.string(forKey: key) ?? fallback }

    /// Names ending in "bot" always count, whatever the list says.
    public static func isBot(_ name: String, list: String? = nil) -> Bool {
        let u = name.lowercased()
        let names = list ?? stored("botNames", defaultNames)
        return u.hasSuffix("bot") || names.lowercased().split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == u }
    }

    /// A bot message holding a trigger word (case-insensitive, whole word): worth the streamer's attention while live.
    public static func isAnnouncement(user: String, text: String, botList: String? = nil, triggers: String? = nil) -> Bool {
        guard isBot(user, list: botList) else { return false }
        func words(_ s: String) -> String { s.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") }
        let body = " " + words(text) + " "
        return (triggers ?? stored("botTriggers", defaultTriggers)).split(separator: ",").contains { t in
            let w = words(String(t))
            return !w.isEmpty && body.contains(" " + w + " ")
        }
    }

    /// Whether Speaker reads this message: non-bots always; bots per botReadMode ("off" | "triggers" | "all").
    public static func reads(_ user: String, _ text: String) -> Bool {
        guard isBot(user) else { return true }
        switch stored("botReadMode", "triggers") {
        case "all": return true
        case "off": return false
        default: return isAnnouncement(user: user, text: text)
        }
    }

    #if DEBUG
    public static func demo() {
        assert(isBot("Nightbot", list: "") && isBot("BotRix", list: "botrix") && !isBot("botanist", list: "botrix"))
        let t = "won, winner"
        assert(isAnnouncement(user: "StreamElements", text: "Bob WON the giveaway!", botList: "streamelements", triggers: t))
        assert(!isAnnouncement(user: "bob", text: "I won", botList: "streamelements", triggers: t))
        assert(!isAnnouncement(user: "nightbot", text: "wonderful day", botList: "", triggers: t))
        assert(!isAnnouncement(user: "nightbot", text: "anything", botList: "", triggers: " , "))
        applog("chat", "BotList.demo() passed")
    }
    #endif
}
