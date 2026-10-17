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

    /// "☁️ 17°", "--" until the first successful fetch; a failed refresh keeps the last value.
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
            value = "\(Self.emoji(now.code)) \(Int(now.temperature.rounded()))°"
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

    /// WMO weather code -> emoji.
    nonisolated static func emoji(_ code: Int) -> String {
        switch code {
        case 0: "☀️"
        case 1, 2: "🌤️"
        case 3: "☁️"
        case 45, 48: "🌫️"
        case 51...67: "🌧️"
        case 71...77: "❄️"
        case 80...82: "🌦️"
        case 85, 86: "🌨️"
        case 95...99: "⛈️"
        default: "🌡️"
        }
    }
}
