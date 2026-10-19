// Plays a donation (tip, Bits, KICKs) as a full-canvas GPU alert instead of the Island banner (see DonationAlert.swift).
// Alerts stay one at a time: the widget loop awaits play() like it awaits AlertPlayer.play.
import CoreGraphics
import Foundation
import HaishinKit

@MainActor
enum DonationAlertPlayer {
    static func play(_ e: ChatEvent, style: AlertWidgetStyle, canvas: CGSize, box: CGRect, goalBox: CGRect?, mixer: MediaMixer) async {
        let kind = style.donationKind, ds = style.donationStyle
        let alert = Self.info(e, goalBox: goalBox)
        let o = await OverlayScreen.makeDonation(CGRect(origin: .zero, size: canvas), kind, alert, ds, box: box)
        await OverlayScreen.add([o], to: mixer)   // added last: on top of everything
        // Layout only re-runs when invalidated, so poke it at 60 Hz (cheap: no drawing here), as for a stinger.
        let poke = Task { @ScreenActor in
            while !Task.isCancelled {
                o.invalidateLayout()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        try? await Task.sleep(for: .seconds(kind.seconds / max(ds.speed, 0.1) + 0.15))   // a beat past the end, so it logs and clears itself
        poke.cancel()
        await OverlayScreen.remove([o], from: mixer)
    }

    private static func symbol(_ code: String) -> String {
        switch code {
        case "IRT": "₮"
        case "USD": "$"
        case "EUR": "€"
        default: code
        }
    }

    static func info(_ e: ChatEvent, goalBox: CGRect?) -> DonationAlertInfo {
        let goalStore = GoalStore.shared, cfg = goalStore.config
        let name = AppBot.safeName(e.user)
        let money: Money? = e.kind == .tip ? e.tipMoney : DonationPrices.money(e)
        let amount = e.kind == .tip ? e.tipMoney.display : "\(e.count) \(e.cheerUnit)"

        // "₮59,000/€": what one unit of the currency it was given in is worth in the goal currency (tips only).
        var rate = ""
        if e.kind == .tip, let m = money?.inToman, m.currency != cfg.currency,
           let r = Rates.shared.convert(Money(1, m.currency), to: cfg.currency) {
            rate = Money(r.rounded(cfg.currency == "IRT" ? 0 : 2), cfg.currency).display + "/" + symbol(m.currency)
        }

        // What it added to the goal: the ledger's value when it is recorded, else converted now.
        let entry = goalStore.entries.first { $0.id == "\(e.origin):\(e.id)" }
        let value = entry?.value ?? money.flatMap { Rates.shared.convert($0, to: cfg.currency) }
        let toGoal = value.map { Money($0.rounded(2), cfg.currency).display } ?? ""

        let usd = money.flatMap { Rates.shared.convert($0, to: "USD") } ?? 0
        let tier = usd < 10 ? 0 : usd < 50 ? 1 : 2

        var goal: DonationAlertInfo.Goal?
        if cfg.target > 0 {
            let v = value ?? 0
            let after = entry == nil ? goalStore.total + v : goalStore.total   // not recorded yet: it is about to be
            let before = max(0, after - v)
            func share(_ x: Decimal) -> Double { min(1, max(0, NSDecimalNumber(decimal: x / cfg.target).doubleValue)) }
            func text(_ x: Decimal) -> String { Money(x.rounded(2), cfg.currency).display }
            goal = DonationAlertInfo.Goal(title: cfg.title, before: text(before), after: text(after), target: text(cfg.target),
                                          from: share(before), to: share(after), box: goalBox)
        }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        let date = f.string(from: e.at).uppercased()
        f.dateFormat = "HH:mm"

        return DonationAlertInfo(name: name, initial: String(name.prefix(1)).uppercased(), amount: amount, message: e.text,
                                 source: e.origin.uppercased(), rate: rate, toGoal: toGoal, tier: tier, date: date,
                                 time: f.string(from: e.at), goal: goal)
    }
}
