// Publishes the goal to the streamer's donate page (CONTEXT.md: Donate page): POST <page>/api/goal with a bearer key.
// Sent when the goal changes, when going live / ending, and every 60 s while live (the page tells LIVE from OFFLINE by
// the heartbeat). At most one request per 5 s. Off while no key is set.
import Foundation
import Combine

@MainActor
final class DonatePagePublisher: ObservableObject {
    static let shared = DonatePagePublisher()
    static let defaultURL = "https://donate.iamsaeed.dev"

    enum Outcome: Equatable { case none, ok(Date), rejected, unreachable, http(Int), badURL }

    @Published private(set) var outcome = Outcome.none

    private let keychain = KeychainTokenStore()
    private var live = false
    private var lastSent = Date.distantPast
    private var scheduled = false
    private var beat: Task<Void, Never>?
    private var loggedKind: String?                  // one log line per kind of failure until it works again
    private var cancellables: Set<AnyCancellable> = []

    // MARK: settings

    var pageURL: String { UserDefaults.standard.string(forKey: "donatePageURL") ?? Self.defaultURL }
    var token: String { keychain.string(forKey: "donatePageToken") ?? "" }
    var enabled: Bool { !token.isEmpty }

    /// The page without its scheme and trailing slash, for chat ("donate.iamsaeed.dev").
    var shortURL: String {
        var u = pageURL.trimmingCharacters(in: .whitespaces)
        for p in ["https://", "http://"] where u.lowercased().hasPrefix(p) { u = String(u.dropFirst(p.count)) }
        while u.hasSuffix("/") { u.removeLast() }
        return u
    }

    func setToken(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        keychain.set(t.isEmpty ? nil : t, forKey: "donatePageToken")
        outcome = .none
        request()
    }

    /// "Published 12 s ago" / "Token rejected" / "Can't reach the page"; empty when off.
    var statusText: String {
        guard enabled else { return "Off: no page key" }
        switch outcome {
        case .none: return "Waiting to publish"
        case .ok(let at): return "Published \(Int(max(0, Date().timeIntervalSince(at)))) s ago"
        case .rejected: return "Token rejected"
        case .unreachable: return "Can't reach the page"
        case .http(let c): return "Page answered HTTP \(c)"
        case .badURL: return "Page URL isn't valid"
        }
    }

    // MARK: triggers

    /// Once, from the App: watches the goal and the streamer's live state.
    func start(streamer: Streamer) {
        guard cancellables.isEmpty else { return }
        GoalStore.shared.objectWillChange
            .sink { [weak self] _ in Task { @MainActor in self?.request() } }   // the Task runs after the change landed
            .store(in: &cancellables)
        streamer.$live
            .sink { [weak self] v in Task { @MainActor in self?.liveChanged(v) } }   // $live emits the new value
            .store(in: &cancellables)
    }

    private func liveChanged(_ v: Bool) {
        live = v
        beat?.cancel()
        beat = nil
        if v {
            beat = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    if !Task.isCancelled { self?.request() }
                }
            }
        }
        request()
    }

    /// Sends now, or when 5 s have passed since the last send; calls in between share that one request.
    func request() {
        guard enabled, !scheduled else { return }
        scheduled = true
        let wait = max(0, 5 - Date().timeIntervalSince(lastSent))
        Task { [self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            scheduled = false
            await send()
        }
    }

    // MARK: sending

    private struct Payload: Encodable {
        let title: String
        let total: Double
        let target: Double
        let currency: String
        let live: Bool
        let updatedAt: String
    }

    /// The JSON body: money as numbers rounded to 2 decimals (toman to 0).
    static func body(title: String, total: Decimal, target: Decimal, currency: String, live: Bool, at: Date) throws -> Data {
        func num(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d.rounded(currency == "IRT" ? 0 : 2)).doubleValue }
        return try JSONEncoder().encode(Payload(title: title, total: num(total), target: num(target), currency: currency,
                                                live: live, updatedAt: ISO8601DateFormatter().string(from: at)))
    }

    private func send() async {
        let key = token
        guard !key.isEmpty else { return }
        guard let url = URL(string: pageURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/goal"),
              url.scheme != nil else { outcome = .badURL; return }
        lastSent = Date()
        let g = GoalStore.shared
        do {
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Test donations move the stream's bar for 10 s but never the public page.
            let tests = g.entries.filter { $0.state == .test }.reduce(Decimal(0)) { $0 + ($1.value ?? 0) }
            req.httpBody = try Self.body(title: g.config.title, total: g.total - tests, target: g.config.target, currency: g.config.currency,
                                         live: live, at: Date())
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) { outcome = .ok(Date()); loggedKind = nil }
            else if code == 401 || code == 403 { fail(.rejected, "HTTP \(code)") }
            else { fail(.http(code), "HTTP \(code)") }
        } catch {
            fail(.unreachable, "unreachable: \(error.localizedDescription)")
        }
    }

    private func fail(_ o: Outcome, _ what: String) {
        outcome = o
        guard loggedKind != what else { return }
        loggedKind = what
        applog("goal", "donate page publish -> \(what)", error: true)
    }

    #if DEBUG
    static func demo() throws {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let eur = try JSONSerialization.jsonObject(with: body(title: "Camera", total: Decimal(string: "12.345")!, target: 500, currency: "EUR", live: true, at: t)) as? [String: Any]
        assert(Set(eur?.keys.map { $0 } ?? []) == ["title", "total", "target", "currency", "live", "updatedAt"])
        assert(abs((eur?["total"] as? Double ?? 0) - 12.35) < 0.0001)
        assert(eur?["target"] as? Double == 500 && eur?["live"] as? Bool == true && eur?["currency"] as? String == "EUR")
        assert((eur?["updatedAt"] as? String)?.hasPrefix("1970-01-12T") == true)
        let irt = try JSONSerialization.jsonObject(with: body(title: "x", total: Decimal(string: "1000.6")!, target: 5_000_000, currency: "IRT", live: false, at: t)) as? [String: Any]
        assert(irt?["total"] as? Double == 1001 && irt?["live"] as? Bool == false)
        applog("goal", "DonatePagePublisher.demo() passed")
    }
    #endif
}
