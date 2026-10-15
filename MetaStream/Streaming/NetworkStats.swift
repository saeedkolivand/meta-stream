// Data behind the in-app NETWORK panel: a 2-minute sample ring, the last bitrate steps, the current
// network path. All main-actor, fed by the existing 1 s stats tick -- no timers of its own.
import Foundation
import Network

struct NetSample {
    let kbps: Int          // actually sent that second
    let target: Int        // adaptive target
    let congested: Bool    // QueueWatcher flagged a backlog
    let down: Bool         // not publishing
}

struct BitrateChange: Identifiable {
    let id = UUID()
    let at: Date
    let kbps: Int
    let up: Bool
    let reason: String     // plain language, see NetworkStats.plainReason
}

extension Array {
    /// Append and drop the oldest beyond `limit` -- the whole "ring buffer".
    mutating func appendCapped(_ element: Element, limit: Int) {
        append(element)
        if count > limit { removeFirst(count - limit) }
    }
}

struct NetworkStats {
    static let sampleLimit = 120
    static let changeLimit = 12

    var samples: [NetSample] = []
    var changes: [BitrateChange] = []     // oldest first; the panel reverses
    var lastDropAt: Date?
    var sessionStart: Date?               // liveSince the buffers belong to; a new value means a new session

    mutating func reset(for start: Date?) {
        samples = []; changes = []; sessionStart = start
    }

    /// True if any of the last `seconds` samples was congested.
    func recentlyCongested(seconds: Int = 5) -> Bool {
        samples.suffix(seconds).contains { $0.congested }
    }

    /// Maps the controller's log reason to something readable mid-walk.
    static func plainReason(_ raw: String) -> String {
        if raw.hasPrefix("queue") { return "network backed up" }
        if raw.hasPrefix("throughput") { return "upload slower than target" }
        if raw.hasPrefix("15s") { return "15 s stable, raising" }
        if raw.hasPrefix("thermal") { return "phone hot" }
        return raw
    }

    /// "2,640 kbps"
    static func fmtKbps(_ kbps: Int) -> String {
        "\(kbps.formatted(.number.grouping(.automatic))) kbps"
    }
}

struct NetPathInfo {
    var status = "Checking"
    var interface = "Other"
    var expensive = false
    var constrained = false

    init() {}

    init(_ p: NWPath) {
        status = p.status == .satisfied ? "Online" : p.status == .unsatisfied ? "Offline" : "Needs connection"
        constrained = p.isConstrained
        expensive = p.isExpensive
        interface = p.usesInterfaceType(.wifi) ? "Wi-Fi"
            : p.usesInterfaceType(.cellular) ? "Cellular"
            : p.usesInterfaceType(.wiredEthernet) ? "Wired" : "Other"
    }

    /// An iPad on an iPhone Personal Hotspot reports Wi-Fi with isExpensive set.
    var label: String { interface == "Wi-Fi" && expensive ? "Wi-Fi (phone hotspot)" : interface }
}

extension Streamer {
    /// Once, from init; app-lifetime, never cancelled (same as the other observers).
    func startNetPathMonitor() {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] p in
            let info = NetPathInfo(p)
            Task { @MainActor in self?.netPath = info }
        }
        m.start(queue: .global())
        pathMonitor = m
    }

    /// Called from the 1 s tick. `congested` is sampled by the caller BEFORE adaptBitrate() consumes the latch.
    func recordNetSample(congested: Bool) {
        guard live else { return }
        if net.sessionStart != liveSince { net.reset(for: liveSince) }
        net.samples.appendCapped(NetSample(kbps: kbps, target: currentBitrateKbps, congested: congested,
                                           down: connectedSince == nil), limit: NetworkStats.sampleLimit)
    }

    func recordBitrateChange(up: Bool, kbps: Int, reason: String) {
        net.changes.appendCapped(BitrateChange(at: Date(), kbps: kbps, up: up, reason: NetworkStats.plainReason(reason)),
                                 limit: NetworkStats.changeLimit)
    }
}
