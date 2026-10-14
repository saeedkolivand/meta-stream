import Foundation

/// Fake chat for the Logs screen's "Chat flood test": deterministic from the index, origin "test" (Speaker ignores it).
enum ChatFlood {
    static let perSecond = 10
    static let seconds = 60

    private static let users = ["viewerOne", "luna_77", "KickFan", "reza_gamer", "bigPogger", "sara.tv", "n00bSlayer", "mod_mike"]
    private static let colors = ["#FF5555", "#55AAFF", "#55FF88", "#FFAA33", "#CC77FF", "#FFDD44"]
    private static let badges: [[String]] = [[], [], ["subscriber"], ["moderator"], ["vip", "subscriber"], ["broadcaster"]]
    private static let texts = [
        "gg that was clean", "first time here, love the stream", "catJAM", "PepeLaugh no way", "EZ clap",
        "این استریم عالیه", "سلام به همه، حالتون چطوره؟", "کی میخواد بازی بعدی رو انتخاب کنه؟ catJAM",
        "lol [emote:37226:KEKW]", "what game is this?", "EZ EZ EZ", "PepeLaugh [emote:37226:KEKW] same",
    ]

    static func event(_ i: Int) -> ChatEvent {
        ChatEvent(kind: .message, user: users[i % users.count], text: texts[(i * 7) % texts.count], origin: "test",
                  badges: badges[(i * 3) % badges.count], color: colors[i % colors.count])
    }
}
