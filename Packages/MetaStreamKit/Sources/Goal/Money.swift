// What each kind of platform event is worth (adr/0006); Money itself lives in CoreModel.
import CoreModel
import Foundation

/// What a sub, a Bit or a KICK is worth: face value, what the viewer paid (adr/0006), editable in Settings › Goal.
/// Stored in UserDefaults as dollar strings so "4.99" stays exact.
public enum DonationPrices {
    /// Strings, not literals: a Decimal float literal goes through Double (4.99 -> 4.990000000000002).
    public static let defaults: [String: String] = [
        "kickSub": "4.99", "twitchTier1": "4.99", "twitchTier2": "9.99", "twitchTier3": "24.99", "youtubeMember": "4.99",
        "bit": "0.01", "kick": "0.01",
    ]

    public static func price(_ key: String) -> Decimal {
        (UserDefaults.standard.string(forKey: "goalPrice." + key) ?? defaults[key]).flatMap { Decimal(string: $0) } ?? 0
    }

    public static func set(_ key: String, _ value: Decimal) {
        UserDefaults.standard.set("\(value)", forKey: "goalPrice." + key)
    }

    /// The money an event carries, in its own currency; nil for events that aren't money (messages, follows, raids).
    /// A gift of n subs is n subs; a sub or resub is one. Bits and KICKs arrive as `.cheer` with a count.
    public static func money(_ e: ChatEvent) -> Money? {
        switch e.kind {
        case .tip:
            return e.money ?? (e.amountCents > 0 ? Money(Decimal(e.amountCents) / 100, "USD") : nil)
        case .cheer:
            guard e.count > 0 else { return nil }
            return Money(Decimal(e.count) * price(e.origin == "kick" ? "kick" : "bit"), "USD")
        case .subscribe:
            let each: Decimal
            switch e.origin {
            case "twitch": each = price("twitchTier\(min(max(e.tier, 1), 3))")
            case "youtube": each = price("youtubeMember")
            default: each = price("kickSub")
            }
            return Money(each * Decimal(max(e.count, 1)), "USD")
        default:
            return nil
        }
    }
}
