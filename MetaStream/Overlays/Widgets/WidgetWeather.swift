// {weather} for live text: current conditions from Open-Meteo (no key), refetched on a slow clock or after a real move.
// Coordinates are rounded to 2 decimals (~1 km) before they leave the phone.
import CoreLocation

private struct Forecast: Decodable {
    struct Now: Decodable {
        let temperature: Double
        let code: Int
        enum CodingKeys: String, CodingKey { case temperature = "temperature_2m", code = "weather_code" }
    }
    let current: Now
}

@MainActor
final class WidgetWeather {
    static let shared = WidgetWeather()

    /// "{i:cloud.fill} 17°" (an inline icon token, see TextRuns), "--" until the first fetch succeeds; a failed refresh keeps it.
    /// Reading it is what turns fetching on, so location never goes to Open-Meteo unless a widget shows {weather}.
    var text: String { wanted = true; return value }
    /// "18°C, clear": no place name, for the app bot's !weather. Reading it turns fetching on too.
    var plainText: String { wanted = true; return plain }
    private var plain = "--"
    private var value = "--"
    private var wanted = false
    private var fetching = false
    private var lastOK: (at: Date, loc: CLLocation)?
    private var lastFail: Date?

    func update(lat: Double, lon: Double) {
        guard wanted, !fetching else { return }
        let loc = CLLocation(latitude: lat, longitude: lon)
        if let f = lastFail, Date().timeIntervalSince(f) < 120 { return }
        if let ok = lastOK, Date().timeIntervalSince(ok.at) < 900, loc.distance(from: ok.loc) <= 5000 { return }
        fetching = true
        let unit = Locale.current.measurementSystem == .metric ? "celsius" : "fahrenheit"
        let url = URL(string: String(format: "https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f"
                                     + "&current=temperature_2m,weather_code&temperature_unit=%@", lat, lon, unit))
        Task {
            defer { fetching = false }
            guard let url, let data = try? await URLSession.shared.data(from: url).0,
                  let now = (try? JSONDecoder().decode(Forecast.self, from: data))?.current else { lastFail = Date(); return }
            value = "{i:\(Self.symbol(now.code))} \(Int(now.temperature.rounded()))°"
            plain = "\(Int(now.temperature.rounded()))°\(unit == "celsius" ? "C" : "F"), \(Self.words(now.code))"
            lastOK = (Date(), loc)
            lastFail = nil
        }
    }

    /// WMO weather code -> plain words.
    nonisolated static func words(_ code: Int) -> String {
        switch code {
        case 0: "clear"
        case 1, 2: "partly cloudy"
        case 3: "overcast"
        case 45, 48: "foggy"
        case 51...67: "rainy"
        case 71...77: "snowy"
        case 80...82: "showers"
        case 85, 86: "snow showers"
        case 95...99: "thunderstorms"
        default: "unsettled"
        }
    }

    /// WMO weather code -> SF Symbol name.
    nonisolated static func symbol(_ code: Int) -> String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...67: "cloud.rain.fill"
        case 71...77: "snowflake"
        case 80...82: "cloud.sun.rain.fill"
        case 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "thermometer.medium"
        }
    }
}
