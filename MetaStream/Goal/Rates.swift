// Market rates for the goal (adr/0006): toman per US dollar from Nobitex's USDT price, US dollars per euro from the
// European Central Bank (frankfurter.app), crypto in dollars from CoinGecko. Refreshed every 10 minutes while the app
// runs and kept across launches. The streamer's own toman rate, when set, replaces Nobitex.
import Foundation

@MainActor
final class Rates: ObservableObject {
    static let shared = Rates()

    struct Quote: Codable, Equatable {
        var value: Decimal
        var at: Date
    }

    @Published private(set) var tomanPerUSD: Quote?   // Nobitex USDT in toman
    @Published private(set) var usdPerEUR: Quote?     // ECB
    @Published private(set) var cryptoUSD: [String: Quote] = [:]
    /// Called after every refresh: pending donations may be convertible now.
    var onUpdate: (() -> Void)?

    /// A market rate older than this is not used (the streamer's rate or pending instead). The ECB publishes
    /// working days only, so its euro rate may be up to a long weekend old.
    static let maxAge: TimeInterval = 24 * 3600
    static let ecbMaxAge: TimeInterval = 4 * 24 * 3600

    /// CoinGecko ids for the coins donation sites take.
    nonisolated static let coins: [String: String] = [
        "BTC": "bitcoin", "ETH": "ethereum", "TON": "the-open-network", "TRX": "tron", "BNB": "binancecoin",
        "SOL": "solana", "LTC": "litecoin", "DOGE": "dogecoin", "XRP": "ripple", "ADA": "cardano", "NOT": "notcoin",
        "USDT": "tether", "USDC": "usd-coin", "DAI": "dai",
    ]

    private var loop: Task<Void, Never>?
    private let key = "goalRates"

    private struct Saved: Codable { var toman: Quote?; var eur: Quote?; var crypto: [String: Quote] }

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            tomanPerUSD = s.toman; usdPerEUR = s.eur; cryptoUSD = s.crypto
        }
    }

    /// The streamer's rate in toman per euro, 0 = none (Settings › Goal).
    var manualTomanPerEUR: Decimal {
        UserDefaults.standard.string(forKey: "goalManualTomanPerEUR").flatMap { Decimal(string: $0) } ?? 0
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    func refresh() async {
        async let toman = Self.fetchNobitex()
        async let eur = Self.fetchECB()
        async let crypto = Self.fetchCoinGecko()
        let (t, e, c) = await (toman, eur, crypto)
        let now = Date()
        if let t { tomanPerUSD = Quote(value: t, at: now) }
        if let e { usdPerEUR = Quote(value: e, at: now) }
        for (sym, v) in c { cryptoUSD[sym] = Quote(value: v, at: now) }
        if let d = try? JSONEncoder().encode(Saved(toman: tomanPerUSD, eur: usdPerEUR, crypto: cryptoUSD)) {
            UserDefaults.standard.set(d, forKey: key)
        }
        applog("goal", "rates: toman/USD \(t.map { "\($0)" } ?? "failed"), USD/EUR \(e.map { "\($0)" } ?? "failed"), \(c.count) coins")
        onUpdate?()
    }

    // MARK: converting

    /// `m` in `target` ("IRT", "USD" or "EUR"), or nil when a rate it needs is missing or too old.
    func convert(_ m: Money, to target: String, now: Date = Date()) -> Decimal? {
        let m = m.inToman
        if m.currency == target { return m.amount }
        guard let usd = usdValue(m, now) else { return nil }
        switch target {
        case "USD": return usd
        case "EUR": return eurRate(now).map { usd / $0 }
        case "IRT": return tomanRate(now).map { usd * $0 }
        default: return nil
        }
    }

    private func usdValue(_ m: Money, _ now: Date) -> Decimal? {
        switch m.currency {
        case "USD", "USDT", "USDC", "DAI": return m.amount   // ponytail: stablecoins at par
        case "EUR": return eurRate(now).map { m.amount * $0 }
        case "IRT": return tomanRate(now).map { m.amount / $0 }
        default: return fresh(cryptoUSD[m.currency], now, Self.maxAge).map { m.amount * $0 }
        }
    }

    private func eurRate(_ now: Date) -> Decimal? { fresh(usdPerEUR, now, Self.ecbMaxAge) }

    /// Toman per dollar: the streamer's rate when set (it overrides), else Nobitex if under a day old.
    func tomanRate(_ now: Date = Date()) -> Decimal? {
        let manual = manualTomanPerEUR
        if manual > 0 {
            // ponytail: the euro-dollar rate barely moves; 1.08 only if it was never fetched.
            let eur = usdPerEUR?.value ?? Decimal(string: "1.08")!
            return manual / eur
        }
        return fresh(tomanPerUSD, now, Self.maxAge)
    }

    private func fresh(_ q: Quote?, _ now: Date, _ maxAge: TimeInterval) -> Decimal? {
        guard let q, q.value > 0, now.timeIntervalSince(q.at) <= maxAge else { return nil }
        return q.value
    }

    /// For Settings: where the toman rate comes from right now.
    var tomanSource: String {
        if manualTomanPerEUR > 0 { return "Your rate" }
        guard let q = tomanPerUSD else { return "No rate yet" }
        let mins = Int(Date().timeIntervalSince(q.at) / 60)
        let age = mins < 60 ? "\(mins) min ago" : "\(mins / 60) h ago"
        return Date().timeIntervalSince(q.at) > Self.maxAge ? "Nobitex, too old (\(age))" : "Nobitex, \(age)"
    }

    // MARK: fetching

    /// Nobitex market stats: {"stats": {"usdt-rls": {"latest": "<rials>"}}}. apiv2 answers from abroad (api.nobitex.ir
    /// doesn't even resolve outside Iran); api is the fallback for networks inside Iran that only reach that one.
    nonisolated static func fetchNobitex() async -> Decimal? {
        for host in ["apiv2.nobitex.ir", "api.nobitex.ir"] {
            guard let url = URL(string: "https://\(host)/market/stats") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(#"{"srcCurrency":"usdt","dstCurrency":"rls"}"#.utf8)
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pair = (json["stats"] as? [String: Any])?["usdt-rls"] as? [String: Any],
               let rials = decimal(pair["latest"]), rials > 0 {
                return rials / 10
            }
        }
        applog("goal", "Nobitex rate unavailable", error: true)
        return nil
    }

    /// {"rates": {"USD": 1.08}}: dollars per euro.
    nonisolated static func fetchECB() async -> Decimal? {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=EUR&to=USD"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let v = decimal((json["rates"] as? [String: Any])?["USD"]), v > 0
        else { return nil }
        return v
    }

    /// {"bitcoin": {"usd": 64000}, ...} for every coin in `coins`.
    nonisolated static func fetchCoinGecko() async -> [String: Decimal] {
        let ids = Set(coins.values).sorted().joined(separator: ",")
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(ids)&vs_currencies=usd"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var out: [String: Decimal] = [:]
        for (sym, id) in coins {
            if let v = decimal((json[id] as? [String: Any])?["usd"]), v > 0 { out[sym] = v }
        }
        return out
    }

    /// A JSON number or numeric string as an exact Decimal (via its text, never through Double arithmetic).
    nonisolated static func decimal(_ v: Any?) -> Decimal? {
        if let s = v as? String { return Decimal(string: s) }
        if let n = v as? NSNumber { return Decimal(string: n.stringValue) }
        return nil
    }
}
