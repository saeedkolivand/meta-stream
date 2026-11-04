// Donations as money (adr/0006): an amount in the currency it was given in. Decimal throughout: currency in
// floating point is a rounding bug waiting to happen.
import Foundation

/// An amount in a currency: "IRT" (toman), "USD", "EUR", or a crypto symbol ("USDT", "BTC", ...).
public struct Money: Codable, Equatable, Hashable, Sendable {
    public var amount: Decimal
    public var currency: String

    public init(_ amount: Decimal, _ currency: String) {
        self.amount = amount
        self.currency = Money.normalize(currency)
    }

    /// Codes as the app keeps them. Rial becomes toman (÷10 is done by `inToman`), Persian spellings are mapped.
    public static func normalize(_ raw: String) -> String {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        switch code {
        case "TOMAN", "TOMANS", "TMN", "IRT", "تومان": return "IRT"
        case "RIAL", "IRR", "RLS", "ریال": return "IRR"
        case "$", "US$", "DOLLAR": return "USD"
        case "€", "EURO": return "EUR"
        default:
            if code.isEmpty { return "USD" }
            // Codes come from donation sites and end up in the bot's chat posts: real ones are 2-6 letters or digits.
            let ok = (2...6).contains(code.count) && code.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
            return ok ? code : "XXX"
        }
    }

    /// Rial is counted as toman (1 toman = 10 rial).
    public var inToman: Money { currency == "IRR" ? Money(amount / 10, "IRT") : self }

    /// "₮1,000,000", "€9.26", "$10", "0.002 BTC".
    public var display: String {
        let money = inToman
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.locale = Locale(identifier: "en_US")
        fmt.maximumFractionDigits = money.currency == "IRT" ? 0 : Money.isFiat(money.currency) ? 2 : 8
        let fraction = money.amount != money.amount.rounded(0)
        fmt.minimumFractionDigits = Money.isFiat(money.currency) && money.currency != "IRT" && fraction ? 2 : 0
        let text = fmt.string(from: money.amount as NSDecimalNumber) ?? "\(money.amount)"
        switch money.currency {
        case "IRT": return "₮" + text
        case "USD": return "$" + text
        case "EUR": return "€" + text
        default: return text + " " + money.currency
        }
    }

    public static func isFiat(_ code: String) -> Bool { ["IRT", "IRR", "USD", "EUR"].contains(code) }
}

extension Decimal {
    public func rounded(_ scale: Int) -> Decimal {
        var value = self, result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
