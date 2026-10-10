import Foundation

/// One Kick inline-emote pattern shared by chat rendering (Emotes) and speech sanitising (Speaker).
/// Single capture group is the numeric id; `*` (not `+`) tolerates an empty name segment.
enum SharedPatterns {
    static let kickEmote = try! NSRegularExpression(pattern: #"\[emote:(\d+):[^\]]*\]"#)
    static let url = try! NSRegularExpression(pattern: #"https?://\S+|\bwww\.\S+"#)
    static let colonEmote = try! NSRegularExpression(pattern: #":[A-Za-z0-9_]+:"#)
    static let mention = try! NSRegularExpression(pattern: #"@(\w+)"#)
}
