// iPhone -> Wi-Fi-only iPad GPS over Personal Hotspot. Those iPads have no GPS chip and tethering doesn't pass the
// phone's fix along, so with "Share GPS with iPad" on, the iPhone answers each UDP ping with its latest fix.
import CoreLocation
import Network

struct SharedFix: Equatable {
    // ponytail: Apple's Personal Hotspot always puts the iPhone at 172.20.10.1; other hotspots are not found.
    static let hotspotIP = IPv4Address("172.20.10.1")!
    static let host = NWEndpoint.Host.ipv4(hotspotIP)
    static let port: NWEndpoint.Port = 47123

    var lat, lon, speed, accuracy: Double
    var time: Date

    var wire: String { "\(lat),\(lon),\(speed),\(accuracy),\(time.timeIntervalSince1970)" }
    /// One log line per exchange, same text on both devices so the two logs line up. No coordinates: the log file persists.
    var summary: String { String(format: "±%.0f m, speed %.1f m/s, fix %.1f s old", accuracy, speed, -time.timeIntervalSinceNow) }

    init(lat: Double, lon: Double, speed: Double, accuracy: Double, time: Date) {
        (self.lat, self.lon, self.speed, self.accuracy, self.time) = (lat, lon, speed, accuracy, time)
    }

    /// nil unless it is five finite numbers in range: the packet comes off the network.
    init?(wire: String) {
        let n = wire.split(separator: ",").compactMap { Double($0) }
        guard n.count == 5, n.allSatisfy(\.isFinite), abs(n[0]) <= 90, abs(n[1]) <= 180, n[2] < 150, n[4] > 0 else { return nil }
        self.init(lat: n[0], lon: n[1], speed: n[2], accuracy: n[3], time: Date(timeIntervalSince1970: n[4]))
    }
}

/// The iPhone side. Runs location in the background while on (needs UIBackgroundModes "location").
@MainActor
final class GPSShare: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = GPSShare()

    private let manager = CLLocationManager()
    private var listener: NWListener?
    @Published private(set) var latest: SharedFix?
    @Published private(set) var lastAsked: Date?   // last iPad ping answered, for GPSOnlyView
    private var loggedReject = false

    func setEnabled(_ on: Bool) {
        listener?.cancel()
        listener = nil
        manager.stopUpdatingLocation()
        guard on else { return }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        do {
            let l = try NWListener(using: .udp, on: SharedFix.port)
            // The iPad opens a fresh connection per ping, so each one gets a single reply and is closed.
            l.newConnectionHandler = { c in
                c.start(queue: .main)
                c.receiveMessage { _, _, _, _ in
                    Task { @MainActor in
                        // Answer only pings that arrived on our own hotspot: on someone else's Wi-Fi, other devices must not read the location.
                        // ponytail: no pairing secret, the hotspot password is the gate; add an HMAC'd request if that's not enough.
                        // Unverified that NWListener connections report localEndpoint; the log shows it if this rejects real pings.
                        guard case .hostPort(.ipv4(let local), _) = c.currentPath?.localEndpoint, local == SharedFix.hotspotIP else {
                            if !self.loggedReject { self.loggedReject = true; applog("location", "GPS share: ignored ping to \(String(describing: c.currentPath?.localEndpoint))") }
                            c.cancel(); return
                        }
                        guard let fix = self.latest else { applog("location", "GPS share: iPad asked, no fix yet"); c.cancel(); return }
                        self.lastAsked = .now
                        applog("location", "GPS share: answered iPad \(fix.summary)")
                        c.send(content: Data(fix.wire.utf8), completion: .contentProcessed { _ in c.cancel() })
                    }
                }
            }
            l.stateUpdateHandler = { if case .failed(let e) = $0 { applog("location", "GPS share listener: \(e)", error: true) } }
            l.start(queue: .main)
            listener = l
            applog("location", "sharing GPS on port \(SharedFix.port)")
        } catch {
            applog("location", "GPS share listener failed: \(error.localizedDescription)", error: true)
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let fix = SharedFix(lat: l.coordinate.latitude, lon: l.coordinate.longitude, speed: l.speed, accuracy: l.horizontalAccuracy, time: l.timestamp)
        Task { @MainActor in self.latest = fix }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in if self.listener != nil { self.manager.startUpdatingLocation() } }
    }
}
