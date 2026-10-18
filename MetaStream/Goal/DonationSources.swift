// Donation sites (CONTEXT.md: Donation source, Missed donation; adr/0006): Donofa (live WebSocket + history), Reymit and
// StreamElements (polled). A donation is recorded in the goal BEFORE it is announced, so one reported twice is announced
// once; ones found in a site's history at launch/reconnect are recorded as missed and never announced.
import Foundation

private struct Parsed {
    enum State { case paid, pending, refunded }
    var id: String
    var name: String
    var message: String
    var money: Money
    var date: Date
    var state: State
}

/// Which JSON keys carry which field, first non-empty one wins (the sites' response shapes are partly undocumented).
private struct Shape: Sendable {
    var id: [String], amount: [String], currency: [String], name: [String], message: [String], date: [String]
    static let donofa = Shape(id: ["id"], amount: ["amount"], currency: ["currency"], name: ["name"], message: ["message"], date: ["created_at"])
    static let reymit = Shape(id: ["id", "_id", "donate_id"], amount: ["amount", "price", "value"], currency: ["currency", "type"],
                              name: ["name", "donator", "donor_name", "user"], message: ["message", "text", "description"],
                              date: ["created_at", "date", "time"])
}

@MainActor
final class DonationHub: ObservableObject {
    static let shared = DonationHub()

    enum Site: String, CaseIterable, Sendable {
        case donofa, reymit, streamelements
        var title: String {
            switch self {
            case .donofa: return "Donofa"
            case .reymit: return "Reymit"
            case .streamelements: return "StreamElements"
            }
        }
        var keyLabel: String {
            switch self {
            case .donofa: return "API key"
            case .reymit: return "API token"
            case .streamelements: return "JWT token"
            }
        }
        var help: String {
            switch self {
            case .donofa: return "Find it in your Donofa panel under API settings."
            case .reymit: return "Find it in Reymit under Settings › Miscellaneous (متفرقه)."
            case .streamelements: return "Dashboard › your profile › Account › Channels › Show secrets (it resets about every two weeks)."
            }
        }
    }

    private enum Outcome { case ok, rejected, unreachable }

    @Published private(set) var status: [Site: String] = [:]

    private static let rejectedText = "Key rejected — paste a new one"
    private let store = KeychainTokenStore()
    private var chat: ChatFeed?
    private var tasks: [Site: Task<Void, Never>] = [:]
    private var sockets: [Site: URLSessionWebSocketTask] = [:]
    private var lastAt: [Site: Date] = [:]
    private var loggedFields: Set<Site> = []

    init() {
        for s in Site.allCases { status[s] = "Not set up" }
    }

    func key(_ site: Site) -> String { store.string(forKey: "donationKey." + site.rawValue) ?? "" }

    func setKey(_ site: Site, _ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { store.removeObject(forKey: "donationKey." + site.rawValue) } else { store.set(k, forKey: "donationKey." + site.rawValue) }
        lastAt[site] = nil
        run(site)
    }

    func start(chat: ChatFeed) {
        self.chat = chat
        for s in Site.allCases { run(s) }
    }

    // MARK: lifecycle

    private func stop(_ site: Site) {
        tasks[site]?.cancel(); tasks[site] = nil
        sockets[site]?.cancel(with: .goingAway, reason: nil); sockets[site] = nil
    }

    /// (Re)starts one site; "Not set up" without a key. Nothing runs before `start(chat:)`.
    private func run(_ site: Site) {
        stop(site)
        let k = key(site)
        guard !k.isEmpty else { status[site] = "Not set up"; return }
        guard chat != nil else { return }
        status[site] = "Connecting…"
        switch site {
        case .donofa:
            tasks[site] = Task { [weak self] in await self?.runDonofa(k) }
        case .reymit:
            let path = k.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? k
            tasks[site] = Task { [weak self] in
                await self?.poll(.reymit, every: 10) { [weak self] in
                    guard let self else { return (.unreachable, []) }
                    let (o, json) = await self.get("https://api.reymit.ir/user/\(path)/donates/last-donates", auth: nil, reject: [401, 403, 404])
                    let raws = Self.items(json)
                    self.logFields(.reymit, raws.first)
                    return (o, raws.compactMap { Self.parse($0, .reymit) })
                }
            }
        case .streamelements:
            tasks[site] = Task { [weak self] in
                var channel = ""
                await self?.poll(.streamelements, every: 15) { [weak self] in
                    guard let self else { return (.unreachable, []) }
                    let auth = "Bearer " + k
                    if channel.isEmpty {
                        let (o, json) = await self.get("https://api.streamelements.com/kappa/v2/channels/me", auth: auth, reject: [401, 403])
                        guard o == .ok else { return (o, []) }
                        guard let id = (json as? [String: Any])?["_id"] as? String else { return (.unreachable, []) }
                        channel = id
                    }
                    let (o, json) = await self.get("https://api.streamelements.com/kappa/v2/tips/\(channel)?limit=25&sort=-createdAt", auth: auth, reject: [401, 403])
                    let raws = Self.items(json)
                    self.logFields(.streamelements, raws.first)
                    return (o, raws.compactMap { Self.parseStreamElements($0) })
                }
            }
        }
    }

    // MARK: Donofa

    private static let donofaBackoff: [UInt64] = [2, 5, 10, 30]

    private func runDonofa(_ key: String) async {
        var attempt = 0
        while !Task.isCancelled {
            if await donofaCatchUp(key) == .rejected { return }
            let r = await donofaSocket(key)
            if Task.isCancelled || r.rejected { return }
            if r.connected { attempt = 0 } else { set(.donofa, "Can't reach Donofa") }
            try? await Task.sleep(for: .seconds(Self.donofaBackoff[min(attempt, Self.donofaBackoff.count - 1)]))
            attempt += 1
        }
    }

    /// The latest 20 donations: anything not already known is recorded as missed. Iran's host first, then the global one.
    private func donofaCatchUp(_ key: String) async -> Outcome {
        var out = Outcome.unreachable
        for base in ["https://api.donofa.ir", "https://api.donofa.com"] {
            let (o, json) = await get(base + "/api/v2/donates/last", auth: "Api " + key, reject: [401, 403])
            out = o
            guard o == .ok else { continue }
            let raws = Self.items(json)
            logFields(.donofa, raws.first)
            ingest(.donofa, raws.compactMap { Self.parse($0, .donofa) }, live: false)
            set(.donofa, connectedText(.donofa))
            return .ok
        }
        if out == .rejected { set(.donofa, Self.rejectedText) } else { set(.donofa, "Can't reach Donofa") }
        return out
    }

    /// Pusher-protocol WebSocket (same approach as KickChatProvider). Returns when the socket ends.
    private func donofaSocket(_ key: String) async -> (rejected: Bool, connected: Bool) {
        guard let url = URL(string: "wss://ws.donofa.com/app/AF5Ed2JK?protocol=7&client=js&version=8.4.0&flash=false") else { return (false, false) }
        let ws = URLSession.shared.webSocketTask(with: url)
        sockets[.donofa] = ws
        ws.resume()
        defer { ws.cancel(with: .goingAway, reason: nil) }
        var connected = false
        do {
            try await ws.send(.string(Self.json(["event": "pusher:subscribe", "data": ["channel": "user." + key]])))
            while !Task.isCancelled {
                guard case .string(let text) = try await ws.receive() else { continue }
                guard let o = Self.object(text), let ev = o["event"] as? String else { continue }
                switch ev {
                case "pusher:ping":
                    try await ws.send(.string(#"{"event":"pusher:pong"}"#))
                case "pusher_internal:subscription_succeeded":
                    connected = true
                    set(.donofa, connectedText(.donofa))
                case "pusher_internal:subscription_error":
                    set(.donofa, Self.rejectedText)
                    return (true, connected)
                case "pusher:error":
                    let d = (o["data"] as? [String: Any]) ?? Self.object(o["data"] as? String ?? "")
                    let code = d?["code"] as? Int ?? 0
                    if code >= 4100 { return (false, connected) }   // 41xx/42xx/43xx: reconnect as the protocol says
                    set(.donofa, Self.rejectedText)
                    return (true, connected)
                default:
                    guard ev.hasSuffix("donate.created") else { continue }   // goal.updated, timer.updated, ...: ignored
                    let inner = (o["data"] as? [String: Any]) ?? Self.object(o["data"] as? String ?? "")
                    // ponytail: the payload may be the donation itself or wrap it; unwrap both guesses.
                    guard let d = (inner?["donate"] as? [String: Any]) ?? (inner?["data"] as? [String: Any]) ?? inner else { continue }
                    logFields(.donofa, d)
                    if let p = Self.parse(d, .donofa) { ingest(.donofa, [p], live: true) }
                }
            }
        } catch {}
        return (false, connected)
    }

    // MARK: polling (Reymit, StreamElements)

    /// The first successful poll is catch-up (unknown ids are missed); later polls are live. A rejected key ends the loop.
    private func poll(_ site: Site, every seconds: Int, fetch: () async -> (Outcome, [Parsed])) async {
        var first = true
        while !Task.isCancelled {
            let (o, items) = await fetch()
            if Task.isCancelled { return }
            switch o {
            case .rejected:
                set(site, Self.rejectedText)
                return
            case .unreachable:
                set(site, "Can't reach \(site.title)")
            case .ok:
                ingest(site, items, live: !first)
                first = false
                set(site, connectedText(site))
            }
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    // MARK: recording

    /// Record first, announce only what was new: a donation reported twice is announced once.
    private func ingest(_ site: Site, _ items: [Parsed], live: Bool) {
        guard !Task.isCancelled, let chat else { return }
        for p in items.sorted(by: { $0.date < $1.date }) {
            let key = site.rawValue + ":" + p.id
            switch p.state {
            case .pending: continue
            case .refunded: GoalStore.shared.refund(key); continue
            case .paid: break
            }
            // A live donation happened just now (some sites' timestamps carry an unknown time zone).
            let at = live ? Date() : p.date
            lastAt[site] = max(lastAt[site] ?? .distantPast, at)
            if live {
                if GoalStore.shared.record(key: key, source: site.rawValue, money: p.money, at: at) {
                    chat.yield(ChatEvent(kind: .tip, user: p.name, text: p.message, money: p.money, origin: site.rawValue, id: p.id))
                }
            } else {
                GoalStore.shared.record(key: key, source: site.rawValue, money: p.money, at: at, missed: true)
            }
        }
    }

    // MARK: status

    /// Only the site's own task writes status after a contact; a cancelled (replaced) task must not overwrite the new one.
    private func set(_ site: Site, _ text: String) {
        guard !Task.isCancelled else { return }
        status[site] = text
    }

    private func connectedText(_ site: Site) -> String {
        guard let t = lastAt[site] else { return "Connected" }
        let mins = max(1, Int(Date().timeIntervalSince(t) / 60))
        let ago = mins < 60 ? "\(mins) min ago" : mins < 2880 ? "\(mins / 60) h ago" : "\(mins / 1440) d ago"
        return "Connected · last donation " + ago
    }

    /// Field names and JSON types of the first raw donation per site (never values): verifies the guessed shapes on device.
    private func logFields(_ site: Site, _ raw: [String: Any]?) {
        guard let raw, loggedFields.insert(site).inserted else { return }
        let fields = raw.keys.sorted().map { k -> String in
            let t: String
            switch raw[k] {
            case is String: t = "string"
            case is NSNumber: t = "number"
            case is [String: Any]: t = "object"
            case is [Any]: t = "array"
            default: t = "null"
            }
            return k + ":" + t
        }
        applog("goal", "\(site.rawValue) donation fields: " + fields.joined(separator: ", "))
    }

    // MARK: HTTP and parsing

    /// GET as JSON. `reject` are the status codes that mean the key is wrong; other failures are "unreachable".
    private func get(_ url: String, auth: String?, reject: Set<Int>) async -> (Outcome, Any?) {
        guard let u = URL(string: url) else { return (.unreachable, nil) }
        var req = URLRequest(url: u, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let auth { req.setValue(auth, forHTTPHeaderField: "Authorization") }
        guard let (data, resp) = try? await URLSession.shared.data(for: req), let code = (resp as? HTTPURLResponse)?.statusCode else {
            return (.unreachable, nil)
        }
        if reject.contains(code) { return (.rejected, nil) }
        guard (200..<300).contains(code) else {
            applog("goal", "donation site HTTP \(code) for \(u.host ?? "")", error: true)
            return (.unreachable, nil)
        }
        return (.ok, try? JSONSerialization.jsonObject(with: data))
    }

    private static func json(_ o: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: o)) ?? Data(), as: UTF8.self)
    }

    private static func object(_ s: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]
    }

    /// The donation objects in a response: a top-level array, or under data/donates/result/docs (nesting allowed).
    private static func items(_ j: Any?) -> [[String: Any]] {
        if let a = j as? [[String: Any]] { return a }
        guard let d = j as? [String: Any] else { return [] }
        for k in ["data", "donates", "result", "docs"] {
            let r = items(d[k])
            if !r.isEmpty { return r }
        }
        return []
    }

    /// A string, number or {code/symbol/name/username} object as text; "" for anything else.
    private static func text(_ v: Any?) -> String {
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? NSNumber { return n.stringValue }
        if let d = v as? [String: Any] {
            for k in ["code", "symbol", "name", "username"] {
                let t = text(d[k])
                if !t.isEmpty { return t }
            }
        }
        return ""
    }

    private static func first(_ d: [String: Any], _ keys: [String]) -> Any? {
        keys.compactMap { d[$0] }.first { !text($0).isEmpty }
    }

    private static func parse(_ d: [String: Any], _ shape: Shape) -> Parsed? {
        let id = text(first(d, shape.id))
        var raw = first(d, shape.amount)
        if let s = raw as? String { raw = s.replacingOccurrences(of: ",", with: "") }
        guard !id.isEmpty, let amount = Rates.decimal(raw), amount > 0 else { return nil }
        var cur = text(first(d, shape.currency))
        if cur.lowercased().hasPrefix("toman") || cur.isEmpty { cur = "IRT" }
        let name = text(first(d, shape.name))
        return Parsed(id: id, name: name.isEmpty ? "Someone" : name, message: text(first(d, shape.message)),
                      money: Money(amount, cur), date: date(first(d, shape.date)) ?? Date(), state: state(d["status"]))
    }

    /// {"_id", "donation": {"user": {"username"}, "message", "amount", "currency"}, "status", "createdAt"} flattened onto `Shape.donofa` keys.
    private static func parseStreamElements(_ d: [String: Any]) -> Parsed? {
        guard let don = d["donation"] as? [String: Any] else { return nil }
        var flat: [String: Any] = [:]
        flat["id"] = d["_id"]; flat["status"] = d["status"]; flat["created_at"] = d["createdAt"]
        flat["name"] = (don["user"] as? [String: Any])?["username"]
        flat["message"] = don["message"]; flat["amount"] = don["amount"]; flat["currency"] = don["currency"]
        return parse(flat, .donofa)
    }

    /// "paid"/1 counts, "refunded"/3 is refunded, anything else is pending; a missing status counts as paid.
    private static func state(_ v: Any?) -> Parsed.State {
        if let s = v as? String {
            switch s.lowercased() {
            case "", "paid", "success", "completed", "succeeded": return .paid
            case "refunded", "refund": return .refunded
            default: return .pending
            }
        }
        if let n = v as? NSNumber { return n.intValue == 1 ? .paid : n.intValue == 3 ? .refunded : .pending }
        return .paid
    }

    /// ISO 8601, "yyyy-MM-dd HH:mm:ss" (taken as UTC: ponytail, the sites don't say) or unix seconds/milliseconds.
    private static func date(_ v: Any?) -> Date? {
        func unix(_ t: Double) -> Date { Date(timeIntervalSince1970: t > 1e12 ? t / 1000 : t) }
        if let s = v as? String {
            if let t = Double(s) { return unix(t) }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
            let l = DateFormatter()
            l.locale = Locale(identifier: "en_US_POSIX")
            l.timeZone = TimeZone(identifier: "UTC")
            l.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return l.date(from: s)
        }
        if let n = v as? NSNumber { return unix(n.doubleValue) }
        return nil
    }
}
