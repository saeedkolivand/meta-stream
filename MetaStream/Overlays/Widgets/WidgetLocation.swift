// Speed and city for the {speed}/{city} text tokens. Location runs only while a live text widget uses it
// (retain/release), so a scene without those tokens never touches the GPS or asks for permission.
import CoreLocation

@MainActor
final class WidgetLocation: NSObject, CLLocationManagerDelegate {
    static let shared = WidgetLocation()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var users = 0
    private var geocoded: (at: Date, loc: CLLocation)?
    private var geocoding = false
    private var metersPerSecond: Double?
    private var city = ""

    /// "42 km/h" (mph in non-metric locales), "--" until the first fix.
    var speedText: String {
        guard let v = metersPerSecond else { return "--" }
        let metric = Locale.current.measurementSystem == .metric
        let n = Int((v * (metric ? 3.6 : 2.23694)).rounded())
        return "\(n < 1 ? 0 : n) \(metric ? "km/h" : "mph")"
    }

    var cityText: String { city.isEmpty ? "--" : city }

    func retain() {
        users += 1
        if users == 1 { start() }
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 { manager.stopUpdatingLocation() }
    }

    private func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break   // denied: the tokens keep showing "--"
        }
    }

    // CLLocationManager callbacks arrive off the main actor; only plain numbers hop across, the CLLocation is rebuilt there.
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let (speed, lat, lon) = (l.speed, l.coordinate.latitude, l.coordinate.longitude)
        Task { @MainActor in self.handle(speed: speed, lat: lat, lon: lon) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in if self.users > 0 { self.start() } }
    }

    private func handle(speed: Double, lat: Double, lon: Double) {
        metersPerSecond = speed >= 0 ? speed : 0   // negative = no valid reading
        let loc = CLLocation(latitude: lat, longitude: lon)
        // At most one reverse geocode per 60 s and 500 m: CLGeocoder is rate limited and a city rarely changes.
        if let g = geocoded, Date().timeIntervalSince(g.at) < 60 || loc.distance(from: g.loc) < 500 { return }
        guard !geocoding else { return }
        geocoding = true
        geocoded = (Date(), loc)
        Task {
            defer { geocoding = false }
            if let name = try? await geocoder.reverseGeocodeLocation(loc).first?.locality { city = name }
        }
    }
}
