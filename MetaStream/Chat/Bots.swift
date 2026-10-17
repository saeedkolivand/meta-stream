import Foundation

/// A saved chat command ("!giveaway start") sent as the streamer. The list lives in AppStorage("botCommands") as JSON.
struct BotCommand: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var destination: String   // "kick" | "twitch" | "all"
    var lockScreen = false

    // ponytail: starters are examples; each bot has its own command names.
    static let seed = encode([BotCommand(text: "!giveaway start", destination: "all"),
                              BotCommand(text: "!giveaway end", destination: "all"),
                              BotCommand(text: "!socials", destination: "all")])
    static func decode(_ raw: String) -> [BotCommand] { (try? JSONDecoder().decode([BotCommand].self, from: Data(raw.utf8))) ?? [] }
    static func encode(_ c: [BotCommand]) -> String { (try? JSONEncoder().encode(c)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    static func stored() -> [BotCommand] { decode(UserDefaults.standard.string(forKey: "botCommands") ?? seed) }

    /// Posted as the streamer's own account: bots like BotRix only obey the broadcaster and mods.
    @MainActor func send(_ p: Platforms) async {
        applog("chat", "command \(text) -> \(destination)")
        if destination != "twitch" { await p.kickSend(text) }
        if destination != "kick" { await p.twitchSend(text) }
    }
}

/// The shared bot list (AppStorage "botNames", comma separated) and what a bot message means for the streamer.
enum BotList {
    static let defaultNames = "nightbot,streamelements,streamlabs,moobot,fossabot,botrix,botrixoficial,kicklet,sery_bot,wizebot,soundalerts"
    static let defaultTriggers = "won, winner"

    private static func stored(_ key: String, _ fallback: String) -> String { UserDefaults.standard.string(forKey: key) ?? fallback }

    /// Names ending in "bot" always count, whatever the list says.
    static func isBot(_ name: String, list: String? = nil) -> Bool {
        let u = name.lowercased()
        let names = list ?? stored("botNames", defaultNames)
        return u.hasSuffix("bot") || names.lowercased().split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == u }
    }

    /// A bot message holding a trigger word (case-insensitive, whole word): worth the streamer's attention while live.
    static func isAnnouncement(user: String, text: String, botList: String? = nil, triggers: String? = nil) -> Bool {
        guard isBot(user, list: botList) else { return false }
        func words(_ s: String) -> String { s.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") }
        let body = " " + words(text) + " "
        return (triggers ?? stored("botTriggers", defaultTriggers)).split(separator: ",").contains { t in
            let w = words(String(t))
            return !w.isEmpty && body.contains(" " + w + " ")
        }
    }

    /// Whether Speaker reads this message: non-bots always; bots per botReadMode ("off" | "triggers" | "all").
    static func reads(_ user: String, _ text: String) -> Bool {
        guard isBot(user) else { return true }
        switch stored("botReadMode", "triggers") {
        case "all": return true
        case "off": return false
        default: return isAnnouncement(user: user, text: text)
        }
    }

    #if DEBUG
    static func demo() {
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
