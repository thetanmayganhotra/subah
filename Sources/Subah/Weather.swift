import Foundation

struct WeatherSnapshot: Codable, Equatable {
    var temp: Double
    var feelsLike: Double
    var precipProb: Int
    var code: Int
    var cloud: Int
    var wind: Double
    var isDay: Bool
    var sunrise: String?
    var sunset: String?
    var placeName: String
    var at: Date

    var summary: String { WeatherService.describe(code) }

    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max" : "moon.stars"
        case 1, 2: return isDay ? "cloud.sun" : "cloud.moon"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51...57: return "cloud.drizzle"
        case 61...67, 80...82: return "cloud.rain"
        case 71...77, 85, 86: return "snowflake"
        case 95...99: return "cloud.bolt.rain"
        default: return "cloud"
        }
    }

    func promptText() -> String {
        var s = "Weather in \(placeName) at wake-up time: \(summary), \(Int(temp.rounded()))°C (feels like \(Int(feelsLike.rounded()))°C), cloud cover \(cloud)%, rain chance \(precipProb)%, wind \(Int(wind.rounded())) km/h, \(isDay ? "already daylight" : "still dark")."
        if let sr = sunrise { s += " Sunrise \(sr)." }
        return s
    }
}

enum WeatherService {
    struct GeoError: LocalizedError { var errorDescription: String? { "Couldn't find that place." } }

    static func geocode(_ query: String) async throws -> Place {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "1"),
                            .init(name: "language", value: "en"), .init(name: "format", value: "json")]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = (json["results"] as? [[String: Any]])?.first,
              let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else { throw GeoError() }
        let parts = [r["name"], r["admin1"], r["country"]].compactMap { $0 as? String }
        var seen = Set<String>()
        let label = parts.filter { seen.insert($0).inserted }.joined(separator: ", ")
        return Place(query: query, name: label, lat: lat, lon: lon, tz: (r["timezone"] as? String) ?? TimeZone.current.identifier)
    }

    static func forecast(_ place: Place, at date: Date) async throws -> WeatherSnapshot {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(place.lat)), .init(name: "longitude", value: String(place.lon)),
            .init(name: "hourly", value: "temperature_2m,apparent_temperature,precipitation_probability,weather_code,cloud_cover,wind_speed_10m,is_day"),
            .init(name: "daily", value: "sunrise,sunset"), .init(name: "timezone", value: place.tz),
            .init(name: "forecast_days", value: "7")
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = json["hourly"] as? [String: Any],
              let times = hourly["time"] as? [String] else { throw GeoError() }
        let tz = place.timeZone
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        var best = 0
        var bestGap = Double.infinity
        for (i, t) in times.enumerated() {
            if let d = f.date(from: t) {
                let gap = abs(d.timeIntervalSince(date))
                if gap < bestGap { bestGap = gap; best = i }
            }
        }
        func num(_ k: String) -> Double { ((hourly[k] as? [Any])?[best] as? NSNumber)?.doubleValue ?? 0 }

        var sunrise: String?
        var sunset: String?
        if let daily = json["daily"] as? [String: Any], let dt = daily["time"] as? [String] {
            let df = DateFormatter()
            df.timeZone = tz
            df.dateFormat = "yyyy-MM-dd"
            let day = df.string(from: date)
            if let i = dt.firstIndex(of: day) {
                let tf = DateFormatter()
                tf.timeZone = tz
                tf.dateFormat = "h:mm a"
                func pretty(_ key: String) -> String? {
                    guard let s = (daily[key] as? [String])?[i], let d = f.date(from: s) else { return nil }
                    return tf.string(from: d)
                }
                sunrise = pretty("sunrise")
                sunset = pretty("sunset")
            }
        }
        return WeatherSnapshot(temp: num("temperature_2m"), feelsLike: num("apparent_temperature"),
                               precipProb: Int(num("precipitation_probability")), code: Int(num("weather_code")),
                               cloud: Int(num("cloud_cover")), wind: num("wind_speed_10m"), isDay: num("is_day") > 0,
                               sunrise: sunrise, sunset: sunset, placeName: place.name.components(separatedBy: ",").first ?? place.name,
                               at: date)
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "clear sky"
        case 1: return "mostly clear"
        case 2: return "partly cloudy"
        case 3: return "overcast"
        case 45, 48: return "foggy"
        case 51...57: return "drizzle"
        case 61...65: return "rain"
        case 66, 67: return "freezing rain"
        case 71...77: return "snow"
        case 80...82: return "rain showers"
        case 85, 86: return "snow showers"
        case 95...99: return "thunderstorm"
        default: return "cloudy"
        }
    }
}

/// Where the Mac is right now, from its public IP (city-level, no permission prompt needed).
enum LocationService {
    static func detect() async -> Place? {
        for url in ["https://ipwho.is/", "https://ipapi.co/json/"] {
            guard let u = URL(string: url), let (data, _) = try? await URLSession.shared.data(from: u),
                  let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let lat = j["latitude"] as? Double, let lon = j["longitude"] as? Double,
                  let city = j["city"] as? String, !city.isEmpty else { continue }
            let region = j["region"] as? String ?? ""
            let country = (j["country"] as? String) ?? (j["country_name"] as? String) ?? ""
            let tz = ((j["timezone"] as? [String: Any])?["id"] as? String) ?? (j["timezone"] as? String) ?? TimeZone.current.identifier
            var seen = Set<String>()
            let label = [city, region, country].filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ", ")
            return Place(query: "", name: label, lat: lat, lon: lon, tz: tz)
        }
        return nil
    }
}
