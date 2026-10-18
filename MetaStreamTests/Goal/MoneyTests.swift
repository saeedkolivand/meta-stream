import XCTest
@testable import MetaStream

final class MoneyTests: XCTestCase {
    func testCurrencyCodesAndRial() {
        XCTAssertEqual(Money(1, "toman").currency, "IRT")
        XCTAssertEqual(Money(1, "تومان").currency, "IRT")
        XCTAssertEqual(Money(1, "rial").currency, "IRR")
        XCTAssertEqual(Money(10_000, "IRR").inToman, Money(1_000, "IRT"))
        XCTAssertEqual(Money(5, "usdt").currency, "USDT")
    }

    func testDisplay() {
        XCTAssertEqual(Money(1_000_000, "IRT").display, "₮1,000,000")
        XCTAssertEqual(Money(10, "USD").display, "$10")
        XCTAssertEqual(Money(Decimal(string: "9.26")!, "EUR").display, "€9.26")
    }

    /// adr/0006 values: Bits and KICKs $0.01, a gift of n subs is n subs, Twitch tiers.
    func testWhatEventsAreWorth() {
        XCTAssertEqual(DonationPrices.money(ChatEvent(kind: .cheer, user: "a", count: 500, origin: "twitch")), Money(5, "USD"))
        XCTAssertEqual(DonationPrices.money(ChatEvent(kind: .cheer, user: "a", count: 100, origin: "kick")), Money(1, "USD"))
        XCTAssertEqual(DonationPrices.money(ChatEvent(kind: .subscribe, user: "a", count: 3, origin: "kick")),
                       Money(Decimal(string: "14.97")!, "USD"))
        XCTAssertEqual(DonationPrices.money(ChatEvent(kind: .subscribe, user: "a", origin: "twitch", tier: 3)),
                       Money(Decimal(string: "24.99")!, "USD"))
        XCTAssertEqual(DonationPrices.money(ChatEvent(kind: .tip, user: "a", money: Money(500, "JPY"), origin: "youtube")), Money(500, "JPY"))
        XCTAssertNil(DonationPrices.money(ChatEvent(kind: .follow, user: "a")))
    }
}
