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
    private var liveTasks: [Site: Task<Void, Never>] = [:]   // StreamElements' realtime socket, beside its polling task
    private var sockets: [Site: URLSessionWebSocketTask] = [:]
    private var logged: [Site: String] = [:]
    private var lastAt: [Site: Date] = [:]
    private var loggedFields: Set<Site> = []
    private var loggedTypes: Set<String> = []   // StreamElements event types whose keys were logged this run
    private var channelIds: [Site: String] = [:]   // StreamElements channel id, shared by the poll and the socket's tip lookup
    private var lastDonofaReal = Date.distantPast   // last donate.created handled on the user channel
    private var loggedWidgetKeys = false

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

    /// The Donofa alert widget identifier (its link's last path component), "" when unset.
    func donofaWidget() -> String { store.string(forKey: "donationKey.donofaWidget") ?? "" }

    /// Accepts the full widget link or a bare identifier; restarts Donofa.
    func setDonofaWidget(_ link: String) {
        let t = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = t.components(separatedBy: "?")[0].components(separatedBy: "#")[0]
            .split(separator: "/").last.map(String.init) ?? ""
        if id.isEmpty { store.removeObject(forKey: "donationKey.donofaWidget") } else { store.set(id, forKey: "donationKey.donofaWidget") }
        run(.donofa)
    }

    func start(chat: ChatFeed) {
        self.chat = chat
        for s in Site.allCases { run(s) }
    }

    // MARK: lifecycle

    private func stop(_ site: Site) {
        tasks[site]?.cancel(); tasks[site] = nil
        liveTasks[site]?.cancel(); liveTasks[site] = nil
        sockets[site]?.cancel(with: .goingAway, reason: nil); sockets[site] = nil
        channelIds[site] = nil
    }

    /// (Re)starts one site; "Not set up" without a key. Nothing runs before `start(chat:)`.
    private func run(_ site: Site) {
        stop(site)
        let k = key(site)
        guard !k.isEmpty else { setStatus(site, "Not set up"); return }
        guard chat != nil else { return }
        setStatus(site, "Connecting…")
        switch site {
        case .donofa:
            let w = donofaWidget()
            tasks[site] = Task { [weak self] in await self?.runDonofa(k, w) }
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
            liveTasks[site] = Task { [weak self] in await self?.runStreamElements(k) }
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
                        self.channelIds[.streamelements] = id
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

    private func runDonofa(_ key: String, _ widget: String) async {
        var attempt = 0
        while !Task.isCancelled {
            if await donofaCatchUp(key) == .rejected { return }
            let r = await donofaSocket(key, widget)
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
            let parsed = raws.compactMap { Self.parse($0, .donofa) }
            let n = ingest(.donofa, parsed, live: false)
            applog("goal", "donofa history ok: \(parsed.count) donations, \(n) new")
            set(.donofa, connectedText(.donofa))
            return .ok
        }
        if out == .rejected { set(.donofa, Self.rejectedText) } else { set(.donofa, "Can't reach Donofa") }
        return out
    }

    /// Pusher-protocol WebSocket (same approach as KickChatProvider). Returns when the socket ends.
    private func donofaSocket(_ key: String, _ widget: String) async -> (rejected: Bool, connected: Bool) {
        guard let url = URL(string: "wss://ws.donofa.com/app/AF5Ed2JK?protocol=7&client=js&version=8.4.0&flash=false") else { return (false, false) }
        let ws = URLSession.shared.webSocketTask(with: url)
        sockets[.donofa] = ws
        ws.resume()
        defer { ws.cancel(with: .goingAway, reason: nil) }
        var connected = false
        do {
            try await ws.send(.string(Self.json(["event": "pusher:subscribe", "data": ["channel": "user." + key]])))
            if !widget.isEmpty {
                try await ws.send(.string(Self.json(["event": "pusher:subscribe", "data": ["channel": "widget." + widget]])))
            }
            applog("goal", "donofa: socket open, subscribing")
            while !Task.isCancelled {
                guard case .string(let text) = try await ws.receive() else { continue }
                guard let o = Self.object(text), let ev = o["event"] as? String else { continue }
                switch ev {
                case "pusher:ping":
                    try await ws.send(.string(#"{"event":"pusher:pong"}"#))
                case "pusher_internal:subscription_succeeded":
                    if (o["channel"] as? String)?.hasPrefix("widget.") == true {
                        applog("goal", "donofa: widget subscription_succeeded")
                        continue
                    }
                    connected = true
                    applog("goal", "donofa: subscription_succeeded")
                    set(.donofa, connectedText(.donofa))
                case "pusher_internal:subscription_error":
                    if (o["channel"] as? String)?.hasPrefix("widget.") == true {   // a bad widget link must not drop the key's connection
                        applog("goal", "donofa: widget subscription_error", error: true)
                        continue
                    }
                    applog("goal", "donofa: subscription_error", error: true)
                    set(.donofa, Self.rejectedText)
                    return (true, connected)
                case "pusher:error":
                    let d = (o["data"] as? [String: Any]) ?? Self.object(o["data"] as? String ?? "")
                    let code = d?["code"] as? Int ?? 0
                    applog("goal", "donofa: pusher:error code \(code)", error: true)
                    if code >= 4100 { return (false, connected) }   // 41xx/42xx/43xx: reconnect as the protocol says
                    set(.donofa, Self.rejectedText)
                    return (true, connected)
                case _ where ev == "widget.action" || ev.hasSuffix("WidgetActionEvent"):
                    let inner = (o["data"] as? [String: Any]) ?? Self.object(o["data"] as? String ?? "")
                    donofaWidgetAction(inner ?? [:])
                default:
                    applog("goal", "donofa event: " + ev)   // names only: tells us what the panel's test donation is called
                    let isTest = ev.lowercased().contains("test")
                    guard isTest || ev.hasSuffix("donate.created") else { continue }   // goal.updated, timer.updated, ...: ignored
                    let inner = (o["data"] as? [String: Any]) ?? Self.object(o["data"] as? String ?? "")
                    // ponytail: the payload may be the donation itself or wrap it; unwrap both guesses.
                    guard let d = (inner?["donate"] as? [String: Any]) ?? (inner?["data"] as? [String: Any]) ?? inner else { continue }
                    if isTest {   // plays the alert, never counts toward the goal
                        var cur = Self.text(Self.first(d, Shape.donofa.currency))
                        if cur.isEmpty || cur.lowercased().hasPrefix("toman") { cur = "IRT" }
                        announceTest(.donofa, name: Self.text(Self.first(d, Shape.donofa.name)), message: Self.text(Self.first(d, Shape.donofa.message)),
                                     amount: Self.first(d, Shape.donofa.amount), currency: cur)
                        continue
                    }
                    logFields(.donofa, d)
                    lastDonofaReal = Date()   // the widget channel's copy of this one is skipped
                    if let p = Self.parse(d, .donofa) { ingest(.donofa, [p], live: true) }
                }
            }
        } catch {}
        return (false, connected)
    }

    /// The alert widget channel carries Donofa's test button (and probably real donations too, which the user channel announced
    /// already): a donation that no real one preceded within 4 s plays as a test, never recorded.
    private func donofaWidgetAction(_ p: [String: Any]) {
        let d = (p["data"] as? [String: Any]) ?? [:]
        if !loggedWidgetKeys {
            loggedWidgetKeys = true
            applog("goal", "donofa widget action keys: \(p.keys.sorted().joined(separator: ", ")), data{\(d.keys.sorted().joined(separator: ", "))}")
        }
        func pick(_ keys: [String]) -> Any? { Self.first(d, keys) ?? Self.first(p, keys) }   // the widget reads u.x ?? e.x
        let type = Self.text(p["type"])
        guard ["donate", "irt", "payment"].contains(type.lowercased()) else {
            applog("goal", "donofa widget action \(type) -> ignored (not a donation)")
            return
        }
        func dec(_ keys: [String]) -> Decimal? {
            var raw = pick(keys)
            if let s = raw as? String { raw = s.replacingOccurrences(of: ",", with: "") }
            guard let a = Rates.decimal(raw), a > 0 else { return nil }
            return a
        }
        let cur = Self.text(pick(["currency"]))
        let money: Money
        if let a = dec(["amount"]), !cur.isEmpty { money = Money(a, cur) }
        else if let a = dec(["amount_irt"]) { money = Money(a, "IRT") }
        else if let a = dec(["amount_usd"]) { money = Money(a, "USD") }
        else if let a = dec(["amount"]) { money = Money(a, "IRT") }
        else {
            applog("goal", "donofa widget action \(type) -> ignored (no amount)")
            return
        }
        let name = Self.text(pick(["name", "username"]))
        let message = Self.text(pick(["message"]))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, let chat = self.chat else { return }
            if Date().timeIntervalSince(self.lastDonofaReal) < 4 {
                applog("goal", "donofa widget action \(type) -> skipped (real donation)")
                return
            }
            applog("goal", "donofa widget action \(type) -> test")
            chat.yield(ChatEvent(kind: .tip, user: name.isEmpty ? "Someone" : name, text: message, amountCents: 0,
                                 money: money, origin: "test-donation"))
        }
    }

    // MARK: StreamElements realtime

    /// Live tips and test events over its socket.io v2 socket; the tips poll stays for catch-up. Reconnects with backoff.
    private func runStreamElements(_ key: String) async {
        var attempt = 0
        while !Task.isCancelled {
            let r = await streamElementsSocket(key)
            if Task.isCancelled || r.rejected { return }
            if r.connected { attempt = 0 }
            try? await Task.sleep(for: .seconds(Self.donofaBackoff[min(attempt, Self.donofaBackoff.count - 1)]))
            attempt += 1
        }
    }

    private func streamElementsSocket(_ key: String) async -> (rejected: Bool, connected: Bool) {
        guard let url = URL(string: "wss://realtime.streamelements.com/socket.io/?cluster=main&EIO=3&transport=websocket") else { return (false, false) }
        let ws = URLSession.shared.webSocketTask(with: url)
        sockets[.streamelements] = ws
        ws.resume()
        var pinger: Task<Void, Never>?
        defer { pinger?.cancel(); ws.cancel(with: .goingAway, reason: nil) }
        var connected = false
        do {
            while !Task.isCancelled {
                guard case .string(let t) = try await ws.receive() else { continue }
                if t.hasPrefix("0{") {   // Engine.IO open: start the keepalive ("2" -> "3")
                    applog("goal", "streamelements: socket open")
                    let ms = (Self.object(String(t.dropFirst()))?["pingInterval"] as? Double) ?? 25000
                    pinger?.cancel()
                    pinger = Task { [ws] in
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(Int(ms)))
                            try? await ws.send(.string("2"))
                        }
                    }
                } else if t == "40" {   // socket.io connect
                    let auth = (try? JSONSerialization.data(withJSONObject: ["authenticate", ["method": "jwt", "token": key]] as [Any])) ?? Data()
                    try await ws.send(.string("42" + String(decoding: auth, as: UTF8.self)))
                } else if t.hasPrefix("41") {
                    return (false, connected)
                } else if t.hasPrefix("42") {
                    let body = String(t.drop { $0.isNumber })
                    guard let arr = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [Any], let name = arr.first as? String else { continue }
                    let p = (arr.count > 1 ? arr[1] as? [String: Any] : nil) ?? [:]
                    switch name {
                    case "authenticated":
                        connected = true
                        applog("goal", "streamelements: authenticated")
                    case "unauthorized":
                        applog("goal", "streamelements: unauthorized", error: true)
                        set(.streamelements, Self.rejectedText)
                        return (true, connected)
                    case "event":
                        let type = Self.text(p["type"])
                        let d = (p["data"] as? [String: Any]) ?? [:]
                        applog("goal", "streamelements event: " + type)
                        logEventKeys(type, p, d)
                        // The dashboard's Emulate buttons arrive as ordinary events: tell them apart before counting or announcing.
                        let flagged = Self.isMock(p) || Self.isMock(d)
                        if type == "tip" {
                            await streamElementsTip(key, p, d, flagged: flagged)
                        } else if flagged {
                            announceTestAlert(type, d)
                        } else {
                            applog("goal", "streamelements \(type) -> real, ignored (the platform delivers it)")
                        }
                    case "event:test":
                        let listener = Self.text(p["listener"])
                        applog("goal", "streamelements test event: " + listener)
                        guard listener.lowercased().hasPrefix("tip"), let e = p["event"] as? [String: Any] else { continue }
                        let cur = Self.text(e["currency"])
                        announceTest(.streamelements, name: Self.text(Self.first(e, ["name", "displayName", "username"])),
                                     message: Self.text(e["message"]), amount: e["amount"], currency: cur.isEmpty ? "USD" : cur)
                    default:
                        applog("goal", "streamelements event: " + name)   // event:update, ...: ignored
                    }
                }
            }
        } catch {}
        return (false, connected)
    }

    /// A socket tip: flagged = test; else real tips are saved by StreamElements (GET 200), emulated ones are not (404/400).
    /// Lookup failures fall back to real; the poll's dedupe key keeps that from double counting.
    private func streamElementsTip(_ key: String, _ p: [String: Any], _ d: [String: Any], flagged: Bool) async {
        let cur = Self.text(d["currency"])
        let currency = cur.isEmpty ? "USD" : cur
        let tipId = Self.text(Self.first(d, ["tipId"]) ?? p["_id"])
        var test = flagged
        var why = "flag"
        if !flagged, !tipId.isEmpty {
            let auth = "Bearer " + key
            var channel = channelIds[.streamelements] ?? ""
            if channel.isEmpty {
                let (o, json) = await get("https://api.streamelements.com/kappa/v2/channels/me", auth: auth, reject: [401, 403])
                if o == .ok, let id = (json as? [String: Any])?["_id"] as? String { channel = id; channelIds[.streamelements] = id }
            }
            let enc = tipId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tipId
            if !channel.isEmpty, let code = await httpStatus("https://api.streamelements.com/kappa/v2/tips/\(channel)/\(enc)", auth: auth),
               code == 404 || code == 400 {
                test = true
                why = "not in store"
            }
        }
        if Task.isCancelled { return }
        if test {
            applog("goal", "streamelements tip -> test (\(why))")
            announceTest(.streamelements, name: Self.text(Self.first(d, ["displayName", "username", "name"])),
                         message: Self.text(d["message"]), amount: d["amount"], currency: currency)
            return
        }
        applog("goal", "streamelements tip -> real")
        var flat: [String: Any] = [:]
        flat["id"] = tipId
        flat["amount"] = d["amount"]
        flat["currency"] = currency
        flat["name"] = Self.first(d, ["displayName", "username"])
        flat["message"] = d["message"]
        if let parsed = Self.parse(flat, .donofa) { ingest(.streamelements, [parsed], live: true) }
    }

    /// An emulated follow/sub/cheer/raid plays its alert (origin "test-donation": never thanked, never recorded).
    private func announceTestAlert(_ type: String, _ d: [String: Any]) {
        guard !Task.isCancelled, let chat else { return }
        let n = Int(Self.text(d["amount"]))
        let kind: ChatEvent.Kind, count: Int
        switch type {
        case "follower", "follow": kind = .follow; count = 0
        case "subscriber": kind = .subscribe; count = 0   // a normal sub; amount is months, and count > 0 would read as a gift of that many
        case "cheer": kind = .cheer; count = n ?? 0
        case "raid", "host": kind = .raid; count = n ?? 0
        default:
            applog("goal", "streamelements \(type) -> test (flag), no alert for this type")
            return
        }
        applog("goal", "streamelements \(type) -> test (flag)")
        let name = Self.text(Self.first(d, ["displayName", "username", "name"]))
        chat.yield(ChatEvent(kind: kind, user: name.isEmpty ? "Someone" : name, text: Self.text(d["message"]), count: count, origin: "test-donation"))
    }

    /// Any of isMock/isTest/mock/test true (Bool or "true") marks an emulated event.
    private static func isMock(_ o: [String: Any]) -> Bool {
        ["isMock", "isTest", "mock", "test"].contains { k in
            if let b = o[k] as? Bool { return b }
            return (o[k] as? String)?.lowercased() == "true"
        }
    }

    /// Key names (never values) of the first event of each type per run: learns where the test flag lives on device.
    private func logEventKeys(_ type: String, _ p: [String: Any], _ d: [String: Any]) {
        guard loggedTypes.insert(type).inserted else { return }
        let top = p.keys.filter { $0 != "data" }.sorted().joined(separator: ", ")
        applog("goal", "streamelements \(type) keys: \(top), data{\(d.keys.sorted().joined(separator: ", "))}")
    }

    /// Status code only (nil when unreachable).
    private func httpStatus(_ url: String, auth: String) async -> Int? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 15)
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        return (resp as? HTTPURLResponse)?.statusCode
    }

    /// A site's test donation plays the alert but is not recorded in the goal.
    private func announceTest(_ site: Site, name: String, message: String, amount: Any?, currency: String) {
        guard !Task.isCancelled, let chat else { return }
        var raw = amount
        if let s = raw as? String { raw = s.replacingOccurrences(of: ",", with: "") }
        guard let a = Rates.decimal(raw), a > 0 else { return }
        applog("goal", "\(site.rawValue) test donation announced")
        chat.yield(ChatEvent(kind: .tip, user: name.isEmpty ? "Someone" : name, text: message, amountCents: 0,
                             money: Money(a, currency), origin: "test-donation"))
    }

    // MARK: polling (Reymit, StreamElements)

    /// The first successful poll is catch-up (unknown ids are missed); later polls are live. A rejected key ends the loop.
    private func poll(_ site: Site, every seconds: Int, fetch: () async -> (Outcome, [Parsed])) async {
        var first = true
        var logged = false
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
                let n = ingest(site, items, live: !first)
                if !logged || n > 0 { applog("goal", "\(site.rawValue) poll ok: \(items.count) donations, \(n) new") }
                logged = true
                first = false
                set(site, connectedText(site))
            }
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    // MARK: recording

    /// Record first, announce only what was new: a donation reported twice is announced once.
    @discardableResult
    private func ingest(_ site: Site, _ items: [Parsed], live: Bool) -> Int {
        guard !Task.isCancelled, let chat else { return 0 }
        var new = 0
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
                if GoalStore.shared.record(key: key, source: site.rawValue, money: p.money, at: at, note: [p.name, p.message].filter { !$0.isEmpty }.joined(separator: " · ")) {
                    chat.yield(ChatEvent(kind: .tip, user: p.name, text: p.message, money: p.money, origin: site.rawValue, id: p.id))
                    new += 1
                }
            } else if GoalStore.shared.record(key: key, source: site.rawValue, money: p.money, at: at, missed: true, note: [p.name, p.message].filter { !$0.isEmpty }.joined(separator: " · ")) {
                new += 1
            }
        }
        return new
    }

    // MARK: status

    /// Only the site's own task writes status after a contact; a cancelled (replaced) task must not overwrite the new one.
    private func set(_ site: Site, _ text: String) {
        guard !Task.isCancelled else { return }
        setStatus(site, text)
    }

    /// Logs each status change once (the "· last donation N min ago" tail is ignored).
    private func setStatus(_ site: Site, _ text: String) {
        status[site] = text
        let head = text.components(separatedBy: " ·")[0]
        guard logged[site] != head else { return }
        logged[site] = head
        applog("goal", "\(site.rawValue): " + head)
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
