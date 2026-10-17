// Bonding: SRTLA sender (BELABOX/srtla srtla_send.c + common.h). libsrt, inside HaishinKit, talks to a loopback UDP
// socket; this proxy sends those packets to the receiver over one UDP socket per network interface and merges the
// replies back. Constants and logic are copied from the reference; names in comments are its identifiers.
import Foundation
import Network

// ponytail: all state is confined to `queue` (every entry point hops onto it), so no locks.
final class Srtla: @unchecked Sendable {
    // common.h
    static let ngp: UInt16 = 0x9211, reg1: UInt16 = 0x9200, reg2: UInt16 = 0x9201, reg3: UInt16 = 0x9202
    static let keepalive: UInt16 = 0x9000, ack: UInt16 = 0x9100, regErr: UInt16 = 0x9210, regNak: UInt16 = 0x9212
    static let srtAck: UInt16 = 0x8002, srtNak: UInt16 = 0x8003
    static let idLen = 256                                   // SRTLA_ID_LEN
    // srtla_send.c
    static let logSize = 256, connTimeout = 4, regTimeout = 4, idleTime = 1   // PKT_LOG_SZ, CONN_TIMEOUT, REG2/3_TIMEOUT, IDLE_TIME
    static let winMin = 1000, winDef = 20_000, winMax = 60_000, winDecr = 100, winIncr = 30   // WINDOW_* x WINDOW_MULT(1000)

    struct Stat: Identifiable, Sendable { let id: String; let label: String; let backup: Bool; let up: Bool; let share: Int }

    final class Link: @unchecked Sendable {   // conn_t
        let name: String, label: String, backup: Bool, conn: NWConnection
        var lastRcvd = 0, lastSent = 0, window = Srtla.winDef, inFlight = 0, idx = 0, sent = 0, share = 0
        var log = [Int32](repeating: -1, count: Srtla.logSize)
        init(name: String, label: String, backup: Bool, conn: NWConnection) { self.name = name; self.label = label; self.backup = backup; self.conn = conn }
        func up(_ now: Int) -> Bool { lastRcvd + Srtla.connTimeout >= now }   // !conn_timed_out
    }

    private let queue = DispatchQueue(label: "srtla")
    private let host: NWEndpoint.Host, port: NWEndpoint.Port
    private let onStats: @Sendable ([Stat]) -> Void
    private var links: [Link] = [], ifaces: [NWInterface] = []
    private var listener: NWListener?, local: NWConnection?, monitor: NWPathMonitor?, timer: DispatchSourceTimer?
    private var started: CheckedContinuation<UInt16, Error>?
    private var id = [UInt8](repeating: 0, count: Srtla.idLen)   // srtla_id
    private var pending: Link?, pendingUntil = 0, active = 0     // pending_reg2_conn, pending_reg_timeout, active_connections
    private var cut = false, ticks = 0

    init?(url: String, onStats: @escaping @Sendable ([Stat]) -> Void) {
        guard let c = URLComponents(string: url), let h = c.host, let p = UInt16(exactly: c.port ?? 5000).flatMap(NWEndpoint.Port.init(rawValue:)) else { return nil }   // ponytail: 5000 = srtla_rec's usual port
        host = NWEndpoint.Host(h); port = p; self.onStats = onStats
        for i in 0..<id.count { id[i] = UInt8.random(in: 0...255) }
    }

    /// Starts the loopback listener and the interface watcher; returns the local port libsrt should connect to.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<UInt16, Error>) in
            queue.async { [self] in
                do {
                    let p = NWParameters.udp
                    p.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                    let l = try NWListener(using: p)
                    listener = l; started = k
                    l.newConnectionHandler = { [self] c in
                        local?.cancel(); local = c      // libsrt reconnects from a fresh socket: the newest one is the peer
                        c.start(queue: queue); recvLocal(c)
                    }
                    l.stateUpdateHandler = { [self] s in
                        switch s {
                        case .ready: started?.resume(returning: l.port?.rawValue ?? 0); started = nil
                        case .failed(let e): started?.resume(throwing: e); started = nil
                        default: break
                        }
                    }
                    l.start(queue: queue)
                } catch { k.resume(throwing: error) }
            }
            let m = NWPathMonitor()
            m.pathUpdateHandler = { [self] path in ifaces = path.availableInterfaces; syncLinks() }
            m.start(queue: queue); queue.async { [self] in monitor = m }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1, repeating: 1); t.setEventHandler { [self] in housekeeping() }
            t.resume(); queue.async { [self] in timer = t }
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel(); monitor?.cancel(); listener?.cancel(); local?.cancel()
            links.forEach { $0.conn.cancel() }; links = []; timer = nil; monitor = nil; listener = nil; local = nil
        }
    }

    /// Bitrate controller has cut below 70% of target: backup links may carry data too.
    func setCut(_ v: Bool) { queue.async { [self] in cut = v } }

    // MARK: pure parts -- see demo()

    static func kind(_ d: [UInt8]) -> UInt16 { d.count < 2 ? 0 : UInt16(d[0]) << 8 | UInt16(d[1]) }   // get_srt_type
    static func be32(_ d: [UInt8], _ at: Int) -> UInt32 { (0..<4).reduce(0) { $0 << 8 | UInt32(d[at + $1]) } }
    /// 31-bit sequence number of an SRT data packet (first bit 0), nil for control packets -- get_srt_sn
    static func seq(_ d: [UInt8]) -> Int32? { d.count < 4 || d[0] & 0x80 != 0 ? nil : Int32(be32(d, 0)) }

    struct Cand { var up: Bool, window: Int, inFlight: Int, backup: Bool }
    /// select_conn(): best window / (in_flight + 1). Main links first; backups only when no main link is up, every
    /// main window is full, or the bitrate has been cut.
    static func pick(_ c: [Cand], cut: Bool) -> Int? {
        let mains = c.indices.filter { c[$0].up && !c[$0].backup }
        let room = mains.contains { c[$0].inFlight * 1000 < c[$0].window }
        let pool = room && !cut ? mains : c.indices.filter { c[$0].up }
        return pool.max { c[$0].window / (c[$0].inFlight + 1) < c[$1].window / (c[$1].inFlight + 1) }
    }

    // MARK: links

    /// Settings: AppStorage "srtlaWifi"/"srtlaEthernet"/"srtlaCellular" = main | backup | off.
    private static func role(_ t: NWInterface.InterfaceType) -> (key: String, label: String, def: String)? {
        switch t {
        case .wifi: return ("srtlaWifi", "Wi-Fi", "main")
        case .wiredEthernet: return ("srtlaEthernet", "Ethernet", "main")
        case .cellular: return ("srtlaCellular", "Cellular", "backup")
        default: return nil
        }
    }

    private func syncLinks() {
        var want: [String: (NWInterface, String, Bool)] = [:]
        for i in ifaces {
            guard let r = Self.role(i.type) else { continue }
            let v = UserDefaults.standard.string(forKey: r.key) ?? r.def
            if v != "off" { want[i.name] = (i, r.label, v == "backup") }
        }
        for l in links where want[l.name] == nil { l.conn.cancel(); links.removeAll { $0 === l }; applog("stream", "srtla: \(l.label) link removed") }
        for (name, w) in want where !links.contains(where: { $0.name == name }) {
            let p = NWParameters.udp
            p.requiredInterface = w.0
            let l = Link(name: name, label: w.1, backup: w.2, conn: NWConnection(host: host, port: port, using: p))
            l.conn.stateUpdateHandler = { [self] s in
                if case .failed = s { links.removeAll { $0 === l }; l.conn.cancel() }   // syncLinks() re-adds it on the next tick
            }
            l.conn.start(queue: queue)
            links.append(l); recv(l)
            applog("stream", "srtla: \(l.label) link added (\(name), \(w.2 ? "backup" : "main"))")
        }
    }

    private func now() -> Int { Int(ProcessInfo.processInfo.systemUptime) }

    private func send(_ l: Link, _ b: [UInt8]) {
        l.conn.send(content: Data(b), completion: .contentProcessed { [self] e in
            if e != nil { queue.async { l.lastRcvd = 1 } }   // sendto() failed: disable the link until re-registered
        })
    }

    private func sendReg(_ l: Link, _ type: UInt16) { send(l, [UInt8(type >> 8), UInt8(type & 0xff)] + id) }   // send_reg1 / send_reg2

    private func housekeeping() {   // connection_housekeeping()
        syncLinks()
        let t = now()
        active = 0
        if pending != nil, t > pendingUntil { pending = nil }
        for l in links {
            if !l.up(t) {
                if l.lastRcvd > 0 {
                    applog("stream", "srtla: \(l.label) link down, re-registering")
                    l.lastRcvd = 0; l.lastSent = 0; l.window = Self.winMin; l.inFlight = 0
                    l.log = [Int32](repeating: -1, count: Self.logSize)
                }
                if pending == nil { sendReg(l, Self.reg2) } else if pending === l { sendReg(l, Self.reg1) }
                continue
            }
            active += 1
            if l.lastSent + Self.idleTime < t { send(l, [0x90, 0x00]) }   // send_keepalive
        }
        ticks += 1
        if ticks % 10 == 0 {
            let total = max(links.reduce(0) { $0 + $1.sent }, 1)
            for l in links { l.share = l.sent * 100 / total; l.sent = 0 }
            applog("stream", "srtla: " + links.map { "\($0.label) \($0.up(t) ? "up" : "down") \($0.share)%" }.joined(separator: ", "))
        }
        onStats(links.map { Stat(id: $0.name, label: $0.label, backup: $0.backup, up: $0.up(t), share: $0.share) })
    }

    // MARK: from libsrt (handle_srt_data)

    private func recvLocal(_ c: NWConnection) {
        c.receiveMessage { [self] d, _, _, e in
            if let d, c === local, !d.isEmpty { fromSRT([UInt8](d)) }
            if e == nil { recvLocal(c) }
        }
    }

    private func fromSRT(_ b: [UInt8]) {
        let t = now()
        let cands = links.map { Cand(up: $0.up(t), window: $0.window, inFlight: $0.inFlight, backup: $0.backup) }
        guard let i = Self.pick(cands, cut: cut) else { return }   // no link up: drop, SRT retransmits
        let l = links[i]
        l.lastSent = t; l.sent += 1
        send(l, b)
        if let sn = Self.seq(b) { l.log[l.idx] = sn; l.idx = (l.idx + 1) % Self.logSize; l.inFlight += 1 }   // reg_pkt
    }

    // MARK: from the receiver (handle_srtla_data)

    private func recv(_ l: Link) {
        l.conn.receiveMessage { [self] d, _, _, e in
            if let d, !d.isEmpty { fromReceiver(l, [UInt8](d)) }
            if e == nil { recv(l) }
        }
    }

    private func fromReceiver(_ l: Link, _ b: [UInt8]) {
        let t = now(), k = Self.kind(b)
        if k == Self.ngp {   // receiver doesn't know our group: start REG1 on this link, only when nothing else is going on
            if active == 0, pending == nil, t > pendingUntil { sendReg(l, Self.reg1); pending = l; pendingUntil = t + Self.regTimeout }
            return
        }
        if k == Self.reg2 {
            if pending === l, b.count >= 2 + Self.idLen, b[2..<(2 + Self.idLen / 2)] == id[0..<(Self.idLen / 2)] {   // first half must match ours
                id = Array(b[2..<(2 + Self.idLen)])
                links.forEach { sendReg($0, Self.reg2) }
                pending = nil; pendingUntil = t + Self.regTimeout
                applog("stream", "srtla: group registered via \(l.label)")
            }
            return
        }
        // ponytail: the reference forwards REG_ERR/REG_NAK to libsrt and counts them as traffic; they are noise, drop them.
        if k == Self.regErr || k == Self.regNak { applog("stream", "srtla: \(l.label) registration refused (0x\(String(k, radix: 16)))", error: true); return }
        l.lastRcvd = t
        switch k {
        case Self.srtAck where b.count >= 20:
            let a = Int32(truncatingIfNeeded: Self.be32(b, 16))   // register_srt_ack: everything below is delivered
            for c in links {
                var n = 0
                for i in 0..<Self.logSize { if c.log[i] < a { c.log[i] = -1 } else { n += 1 } }
                c.inFlight = n
            }
        case Self.srtNak:
            var i = 16
            while i + 4 <= b.count {
                let v = Self.be32(b, i); i += 4
                if v & 0x8000_0000 != 0, i + 4 <= b.count {   // range: first has the high bit, next is the last lost
                    let last = Self.be32(b, i); i += 4
                    if v & 0x7FFF_FFFF <= last { for s in (v & 0x7FFF_FFFF)...last { nak(Int32(truncatingIfNeeded: s)) } }
                } else { nak(Int32(truncatingIfNeeded: v)) }
            }
        case Self.ack:   // SRTLA ACK: a list of acknowledged sequence numbers
            var i = 4
            while i + 4 <= b.count { srtlaAck(Int32(truncatingIfNeeded: Self.be32(b, i))); i += 4 }
            return
        case Self.keepalive: return
        case Self.reg3: active += 1; applog("stream", "srtla: \(l.label) link registered"); return
        default: break
        }
        local?.send(content: Data(b), completion: .idempotent)
    }

    private func nak(_ s: Int32) {   // register_nak: shrink the window of the link that carried it
        for c in links {
            if let i = c.log.firstIndex(of: s) { c.log[i] = -1; c.window = max(c.window - Self.winDecr, Self.winMin); return }
        }
    }

    private func srtlaAck(_ s: Int32) {   // register_srtla_ack
        var found = false
        for c in links {
            if !found, let i = c.log.firstIndex(of: s) {
                found = true; c.log[i] = -1
                if c.inFlight > 0 { c.inFlight -= 1 }
                if c.inFlight * 1000 > c.window { c.window += Self.winIncr - 1 }
            }
            if c.lastRcvd != 0 { c.window = min(c.window + 1, Self.winMax) }
        }
    }

    #if DEBUG
    static func demo() {
        assert(kind([0x92, 0x01]) == reg2 && kind([0x90]) == 0)
        assert(seq([0x00, 0x00, 0x01, 0x02, 0, 0]) == 258 && seq([0x80, 0x02, 0, 0]) == nil && seq([0]) == nil)
        assert(be32([0, 0, 0, 0, 0, 0, 1, 0], 4) == 256)
        let wifi = Cand(up: true, window: 20_000, inFlight: 3, backup: false)
        let cell = Cand(up: true, window: 20_000, inFlight: 0, backup: true)
        assert(pick([wifi, cell], cut: false) == 0)                                   // main wins even with a better-scoring backup
        assert(pick([wifi, cell], cut: true) == 1)                                    // bitrate cut: backup helps
        var full = wifi; full.inFlight = 20
        assert(pick([full, cell], cut: false) == 1)                                   // main window full
        var down = wifi; down.up = false
        assert(pick([down, cell], cut: false) == 1)                                   // no main up
        assert(pick([down], cut: false) == nil)
        applog("stream", "Srtla.demo() passed")
    }
    #endif
}
