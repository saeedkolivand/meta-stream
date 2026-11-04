import Foundation

/// One Kick inline-emote pattern shared by chat rendering (Emotes) and speech sanitising (Speaker).
/// Single capture group is the numeric id; `*` (not `+`) tolerates an empty name segment.
public enum SharedPatterns {
    public static let kickEmote = NSRegularExpression.literal(#"\[emote:(\d+):[^\]]*\]"#)
    public static let url = NSRegularExpression.literal(#"https?://\S+|\bwww\.\S+"#)
    public static let colonEmote = NSRegularExpression.literal(#":[A-Za-z0-9_]+:"#)
    public static let mention = NSRegularExpression.literal(#"@(\w+)"#)
}
