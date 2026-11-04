// Data behind the in-app NETWORK panel: a 2-minute sample ring, the last bitrate steps, the current
// network path. All main-actor, fed by the existing 1 s stats tick -- no timers of its own.
import Foundation
import Network

public struct NetSample {
    public let kbps: Int          // actually sent that second
    public let target: Int        // adaptive target
    public let congested: Bool    // QueueWatcher flagged a backlog
    public let down: Bool         // not publishing

    public init(kbps: Int, target: Int, congested: Bool, down: Bool) {
        self.kbps = kbps
        self.target = target
        self.congested = congested
        self.down = down
    }
}

public struct BitrateChange: Identifiable {
    public let id = UUID()
    public let at: Date
    public let kbps: Int
    public let up: Bool
    public let reason: String     // plain language, see NetworkStats.plainReason

    public init(at: Date, kbps: Int, up: Bool, reason: String) {
        self.at = at
        self.kbps = kbps
        self.up = up
        self.reason = reason
    }
}

extension Array {
    /// Append and drop the oldest beyond `limit` -- the whole "ring buffer".
    public mutating func appendCapped(_ element: Element, limit: Int) {
        append(element)
        if count > limit { removeFirst(count - limit) }
    }
}

public struct NetworkStats {
    public static let sampleLimit = 120
    public static let changeLimit = 12

    public var samples: [NetSample] = []
    public var changes: [BitrateChange] = []     // oldest first; the panel reverses
    public var lastDropAt: Date?
    public var sessionStart: Date?               // liveSince the buffers belong to; a new value means a new session

    public mutating func reset(for start: Date?) {
        samples = []; changes = []; sessionStart = start
    }

    /// True if any of the last `seconds` samples was congested.
    public func recentlyCongested(seconds: Int = 5) -> Bool {
        samples.suffix(seconds).contains { $0.congested }
    }

    /// Maps the controller's log reason to something readable mid-walk.
    public static func plainReason(_ raw: String) -> String {
        if raw.hasPrefix("queue") { return "network backed up" }
        if raw.hasPrefix("throughput") { return "upload slower than target" }
        if raw.hasPrefix("15s") { return "15 s stable, raising" }
        if raw.hasPrefix("thermal") { return "phone hot" }
        return raw
    }

    /// "2,640 kbps"
    public static func fmtKbps(_ kbps: Int) -> String {
        "\(kbps.formatted(.number.grouping(.automatic))) kbps"
    }

    public init(samples: [NetSample] = [], changes: [BitrateChange] = [], lastDropAt: Date? = nil, sessionStart: Date? = nil) {
        self.samples = samples
        self.changes = changes
        self.lastDropAt = lastDropAt
        self.sessionStart = sessionStart
    }
}

public struct NetPathInfo {
    public var status = "Checking"
    public var interface = "Other"
    public var expensive = false
    public var constrained = false

    public init() {}

    public init(_ p: NWPath) {
        status = p.status == .satisfied ? "Online" : p.status == .unsatisfied ? "Offline" : "Needs connection"
        constrained = p.isConstrained
        expensive = p.isExpensive
        interface = p.usesInterfaceType(.wifi) ? "Wi-Fi"
            : p.usesInterfaceType(.cellular) ? "Cellular"
            : p.usesInterfaceType(.wiredEthernet) ? "Wired" : "Other"
    }

    /// An iPad on an iPhone Personal Hotspot reports Wi-Fi with isExpensive set.
    public var label: String { interface == "Wi-Fi" && expensive ? "Wi-Fi (phone hotspot)" : interface }
}

extension Streamer {
    /// Once, from init; app-lifetime, never cancelled (same as the other observers).
    public func startNetPathMonitor() {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] p in
            let info = NetPathInfo(p)
            Task { @MainActor in self?.netPath = info }
        }
        m.start(queue: .global())
        pathMonitor = m
    }

    /// Called from the 1 s tick. `congested` is sampled by the caller BEFORE adaptBitrate() consumes the latch.
    public func recordNetSample(congested: Bool) {
        guard live else { return }
        if net.sessionStart != liveSince { net.reset(for: liveSince) }
        net.samples.appendCapped(NetSample(kbps: kbps, target: currentBitrateKbps, congested: congested,
                                           down: connectedSince == nil), limit: NetworkStats.sampleLimit)
    }

    public func recordBitrateChange(up: Bool, kbps: Int, reason: String) {
        net.changes.appendCapped(BitrateChange(at: Date(), kbps: kbps, up: up, reason: NetworkStats.plainReason(reason)),
                                 limit: NetworkStats.changeLimit)
    }
}
