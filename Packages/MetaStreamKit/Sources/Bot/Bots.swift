import Chat
import CoreLogging
import Foundation
import Platforms

/// A saved chat command ("!giveaway start") sent as the streamer. The list lives in AppStorage("botCommands") as JSON.
struct BotCommand: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var destination: String   // "kick" | "twitch" | "all"
    var lockScreen = false

    // ponytail: starters are examples; each bot has its own command names.
    static let seed = encode([BotCommand(text: "/clear", destination: "all"),
                              BotCommand(text: "!giveaway start", destination: "all"),
                              BotCommand(text: "!giveaway end", destination: "all"),
                              BotCommand(text: "!socials", destination: "all")])
    static func decode(_ raw: String) -> [BotCommand] { (try? JSONDecoder().decode([BotCommand].self, from: Data(raw.utf8))) ?? [] }
    static func encode(_ c: [BotCommand]) -> String { (try? JSONEncoder().encode(c)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    static func stored() -> [BotCommand] { decode(UserDefaults.standard.string(forKey: "botCommands") ?? seed) }

    /// "/clear" joined the starters after people already had lists: added to theirs once (deletable like any chip).
    static func addClearOnce() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "botCommandsClearAdded") else { return }
        d.set(true, forKey: "botCommandsClearAdded")
        guard let raw = d.string(forKey: "botCommands") else { return }   // still on the seed, which has it
        var list = decode(raw)
        guard !list.contains(where: { $0.text.lowercased() == "/clear" }) else { return }
        list.insert(BotCommand(text: "/clear", destination: "all"), at: 0)
        d.set(encode(list), forKey: "botCommands")
    }

    /// Posted as the streamer's own account: bots like BotRix only obey the broadcaster and mods. A "/command" is
    /// never posted: it runs like a typed slash command on each platform it targets. Returns that outcome ("" otherwise).
    @MainActor @discardableResult func send(_ p: Platforms, chat: ChatFeed) async -> String {
        applog("chat", "command \(text) -> \(destination)")
        if let c = SlashCommand.parse(text) {
            var notes: [String] = []
            for origin in ["kick", "twitch"] where destination == "all" || destination == origin {
                if origin == "twitch", !p.twitchConnected { continue }
                notes.append(await SlashRunner(p: p, chat: chat, origin: origin).run(c.name, c.args))
            }
            let note = notes.filter { !$0.isEmpty }.joined(separator: " · ")
            applog("chat", "command \(text): \(note)")
            return note
        }
        if destination != "twitch" { await p.kickSend(text) }
        if destination != "kick" { await p.twitchSend(text) }
        return ""
    }
}
