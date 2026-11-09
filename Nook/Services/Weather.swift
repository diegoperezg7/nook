import Foundation
import Observation

/// Tiempo actual de la ciudad elegida en Ajustes, de Open-Meteo (sin cuenta ni
/// clave). Solo se envian las coordenadas de esa ciudad; sin ciudad no se pide nada.
@Observable
@MainActor
final class Weather {
    struct Current: Equatable {
        let temperature: Double
        let code: Int
        let city: String

        /// Simbolo segun el codigo WMO.
        var symbol: String {
            switch code {
            case 0: return "sun.max.fill"
            case 1, 2: return "cloud.sun.fill"
            case 3: return "cloud.fill"
            case 45, 48: return "cloud.fog.fill"
            case 51...57: return "cloud.drizzle.fill"
            case 61...67, 80...82: return "cloud.rain.fill"
            case 71...77, 85, 86: return "cloud.snow.fill"
            case 95...99: return "cloud.bolt.rain.fill"
            default: return "cloud.fill"
            }
        }
    }

    struct Place: Equatable, Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private(set) var current: Current?
    @ObservationIgnored private var updated: Date?

    static var savedPlace: Place? {
        let defaults = UserDefaults.standard
        guard let name = defaults.string(forKey: SettingsKey.weatherCity), !name.isEmpty else { return nil }
        return Place(name: name, latitude: defaults.double(forKey: SettingsKey.weatherLatitude),
                     longitude: defaults.double(forKey: SettingsKey.weatherLongitude))
    }

    /// Como mucho una peticion cada 15 minutos.
    func refreshIfNeeded() {
        guard let place = Self.savedPlace else { current = nil; return }
        if let updated, Date.now.timeIntervalSince(updated) < 15 * 60, current?.city == place.name { return }
        updated = .now
        Task {
            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: String(place.latitude)),
                URLQueryItem(name: "longitude", value: String(place.longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            ]
            struct Response: Decodable {
                struct Values: Decodable { let temperature_2m: Double; let weather_code: Int }
                let current: Values
            }
            guard let url = components.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let response = try? JSONDecoder().decode(Response.self, from: data) else { updated = nil; return }
            current = Current(temperature: response.current.temperature_2m, code: response.current.weather_code, city: place.name)
        }
    }

    /// Busca una ciudad por nombre (Ajustes).
    static func search(_ name: String) async -> Place? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "es"),
        ]
        struct Response: Decodable { let results: [Place]? }
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return (try? JSONDecoder().decode(Response.self, from: data))?.results?.first
    }
}
