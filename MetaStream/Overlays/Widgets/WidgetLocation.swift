// Speed, distance, city and weather for the {speed}/{distance}/{city}/{weather} tokens. Location runs only while a live text widget uses it
// (retain/release), so a scene without those tokens never touches the GPS or asks for permission.
import CoreLocation
import MapKit
import Network
import UIKit

@MainActor
final class WidgetLocation: NSObject, CLLocationManagerDelegate {
    static let shared = WidgetLocation()

    private let manager = CLLocationManager()
    private var users = 0
    private var geocoded: (at: Date, loc: CLLocation)?
    private var geocoding = false
    private var metersPerSecond: Double?
    private var city = ""
    private var region = ""           // "Tehran Province, Iran": for the app bot's !location, never the city
    private var meters = 0.0           // driven since distanceKey (the go-live time), reset when a new stream starts
    private var distanceKey: Date?
    private var lastFix: CLLocation?   // last accurate fix, the start of the next distance leg
    private var loggedFix = false
    private var phonePoll: Task<Void, Never>?   // iPad only: asks the hotspot iPhone for its GPS (see GPSShare)
    private var phoneFixAt = Date.distantPast
    private var phoneTime: Date?
    private var phoneSilent = false   // logs "no reply" once per outage, not every second

    /// "42 km/h" (mph in non-metric locales), "--" until the first fix.
    var speedText: String {
        guard let v = metersPerSecond else { return "--" }
        let metric = Locale.current.measurementSystem == .metric
        let n = Int((v * (metric ? 3.6 : 2.23694)).rounded())
        return "\(n < 1 ? 0 : n) \(metric ? "km/h" : "mph")"
    }

    /// "3.4 km" (mi in non-metric locales) travelled since the stream went live; 0.0 until a moving, accurate fix.
    func distanceText(since: Date?) -> String {
        if since != distanceKey { distanceKey = since; meters = 0 }
        let metric = Locale.current.measurementSystem == .metric
        return metric ? String(format: "%.1f km", meters / 1000) : String(format: "%.1f mi", meters / 1609.344)
    }

    /// Province/state and country only; nil until the first geocode.
    var regionText: String? { region.isEmpty ? nil : region }

    var cityText: String { city.isEmpty ? "--" : city }

    func retain() {
        users += 1
        if users == 1 {
            start()
            if UIDevice.current.userInterfaceIdiom == .pad { phonePoll = pollPhone() }
        }
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 { manager.stopUpdatingLocation(); lastFix = nil; loggedFix = false; phonePoll?.cancel(); phonePoll = nil; phoneTime = nil }
    }

    private func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        applog("location", "start, authorization \(manager.authorizationStatus.rawValue)")
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break   // denied: the tokens keep showing "--"
        }
    }

    // CLLocationManager callbacks arrive off the main actor; only plain numbers hop across, the CLLocation is rebuilt there.
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let (speed, lat, lon, acc, time) = (l.speed, l.coordinate.latitude, l.coordinate.longitude, l.horizontalAccuracy, l.timestamp)
        Task { @MainActor in
            guard Date().timeIntervalSince(self.phoneFixAt) > 5 else { return }   // the iPhone's GPS wins while it answers
            self.handle(speed: speed, lat: lat, lon: lon, accuracy: acc, time: time)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in if self.users > 0 { self.start() } }
    }

    /// Pings the iPhone once a second on a fresh UDP connection, so a phone that starts sharing later is still found.
    /// Each connection waits 3 s for its reply: on a congested hotspot a reply can arrive after the next ping went out.
    private func pollPhone() -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                let c = NWConnection(host: SharedFix.host, port: SharedFix.port, using: SharedFix.params)
                c.start(queue: .global())
                c.receiveMessage { data, _, _, _ in
                    guard let data, let fix = SharedFix(wire: String(decoding: data, as: UTF8.self)) else { return }
                    Task { @MainActor in self.phoneFix(fix) }
                }
                c.send(content: Data("?".utf8), completion: .idempotent)
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { c.cancel() }
                try? await Task.sleep(for: .seconds(1))
                if !phoneSilent, Date().timeIntervalSince(phoneFixAt) > 4 { phoneSilent = true; applog("location", "iPhone GPS: no reply") }
            }
        }
    }

    private func phoneFix(_ f: SharedFix) {
        guard phonePoll != nil else { return }
        if phoneSilent {
            phoneSilent = false
            if phoneFixAt != .distantPast { applog("location", "iPhone GPS: replies again after \(Int(Date().timeIntervalSince(phoneFixAt))) s") }
        }
        phoneFixAt = Date()
        guard f.time != phoneTime else { return }   // the phone repeats its latest fix until a new one arrives
        if phoneTime == nil { applog("location", "using iPhone GPS: accuracy \(Int(f.accuracy)) m, speed \(f.speed)") }
        phoneTime = f.time
        handle(speed: f.speed, lat: f.lat, lon: f.lon, accuracy: f.accuracy, time: f.time)
    }

    private func handle(speed: Double, lat: Double, lon: Double, accuracy: Double, time: Date) {
        // Negative = no GPS speed (e.g. Wi-Fi-only iPads, which have no GPS): show "--", not a fake 0.
        if !loggedFix { loggedFix = true; applog("location", "first fix: accuracy \(Int(accuracy)) m, speed \(speed)") }
        metersPerSecond = speed >= 0 ? speed : nil
        let loc = CLLocation(latitude: lat, longitude: lon)
        if accuracy >= 0, accuracy <= 30 {
            if let prev = lastFix {
                let d = loc.distance(from: prev), dt = time.timeIntervalSince(prev.timestamp)
                // Only while moving (a parked car must not creep) and not across GPS jumps (> 70 m/s).
                if speed >= 1, dt <= 0 || d / dt <= 70 { meters += d }
            }
            lastFix = CLLocation(coordinate: loc.coordinate, altitude: 0, horizontalAccuracy: accuracy,
                                 verticalAccuracy: -1, timestamp: time)
        }
        WidgetWeather.shared.update(lat: lat, lon: lon)
        // At most one reverse geocode per 60 s and 500 m: geocoding is rate limited and a city rarely changes.
        if let g = geocoded, Date().timeIntervalSince(g.at) < 60 || loc.distance(from: g.loc) < 500 { return }
        guard !geocoding else { return }
        geocoding = true
        geocoded = (Date(), loc)
        guard let request = MKReverseGeocodingRequest(location: loc) else { geocoding = false; return }
        Task {
            defer { geocoding = false }
            let item = (try? await request.mapItems)?.first
            if let name = item?.addressRepresentations?.cityName { city = name }
            // ponytail: rides the city geocode (already throttled to 60 s / 500 m) instead of a second CLGeocoder call.
            if let pm = item?.placemark {
                var parts = [pm.administrativeArea, pm.country].compactMap { $0 }
                if parts.count == 2, parts[0] == parts[1] { parts.removeLast() }
                region = parts.joined(separator: ", ")
            }
        }
    }
}
