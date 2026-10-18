// Donations as money (adr/0006): an amount in the currency it was given in, and what each kind of platform event is
// worth. Decimal throughout: currency in floating point is a rounding bug waiting to happen.
import Foundation

/// An amount in a currency: "IRT" (toman), "USD", "EUR", or a crypto symbol ("USDT", "BTC", ...).
struct Money: Codable, Equatable, Hashable, Sendable {
    var amount: Decimal
    var currency: String

    init(_ amount: Decimal, _ currency: String) {
        self.amount = amount
        self.currency = Money.normalize(currency)
    }

    /// Codes as the app keeps them. Rial becomes toman (÷10 is done by `inToman`), Persian spellings are mapped.
    static func normalize(_ raw: String) -> String {
        let c = raw.trimmingCharacters(in: .whitespaces).uppercased()
        switch c {
        case "TOMAN", "TOMANS", "TMN", "IRT", "تومان": return "IRT"
        case "RIAL", "IRR", "RLS", "ریال": return "IRR"
        case "$", "US$", "DOLLAR": return "USD"
        case "€", "EURO": return "EUR"
        default:
            if c.isEmpty { return "USD" }
            // Codes come from donation sites and end up in the bot's chat posts: real ones are 2-6 letters or digits.
            let ok = (2...6).contains(c.count) && c.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
            return ok ? c : "XXX"
        }
    }

    /// Rial is counted as toman (1 toman = 10 rial).
    var inToman: Money { currency == "IRR" ? Money(amount / 10, "IRT") : self }

    /// "₮1,000,000", "€9.26", "$10", "0.002 BTC".
    var display: String {
        let m = inToman
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = m.currency == "IRT" ? 0 : Money.isFiat(m.currency) ? 2 : 8
        f.minimumFractionDigits = Money.isFiat(m.currency) && m.currency != "IRT" && m.amount != m.amount.rounded(0) ? 2 : 0
        let n = f.string(from: m.amount as NSDecimalNumber) ?? "\(m.amount)"
        switch m.currency {
        case "IRT": return "₮" + n
        case "USD": return "$" + n
        case "EUR": return "€" + n
        default: return n + " " + m.currency
        }
    }

    static func isFiat(_ c: String) -> Bool { ["IRT", "IRR", "USD", "EUR"].contains(c) }
}

extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var v = self, r = Decimal()
        NSDecimalRound(&r, &v, scale, .plain)
        return r
    }
}

/// What a sub, a Bit or a KICK is worth: face value, what the viewer paid (adr/0006), editable in Settings › Goal.
/// Stored in UserDefaults as dollar strings so "4.99" stays exact.
enum DonationPrices {
    /// Strings, not literals: a Decimal float literal goes through Double (4.99 -> 4.990000000000002).
    static let defaults: [String: String] = [
        "kickSub": "4.99", "twitchTier1": "4.99", "twitchTier2": "9.99", "twitchTier3": "24.99", "youtubeMember": "4.99",
        "bit": "0.01", "kick": "0.01",
    ]

    static func price(_ key: String) -> Decimal {
        (UserDefaults.standard.string(forKey: "goalPrice." + key) ?? defaults[key]).flatMap { Decimal(string: $0) } ?? 0
    }

    static func set(_ key: String, _ value: Decimal) {
        UserDefaults.standard.set("\(value)", forKey: "goalPrice." + key)
    }

    /// The money an event carries, in its own currency; nil for events that aren't money (messages, follows, raids).
    /// A gift of n subs is n subs; a sub or resub is one. Bits and KICKs arrive as `.cheer` with a count.
    static func money(_ e: ChatEvent) -> Money? {
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
