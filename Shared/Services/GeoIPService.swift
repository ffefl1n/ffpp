import Foundation

public struct GeoLocation: Codable {
    public let countryCode: String
    public let countryName: String
    public let city: String?
    public let flag: String
}

public final class GeoIPService {
    public static let shared = GeoIPService()
    private var cache: [String: GeoLocation] = [:]
    private let queue = DispatchQueue(label: "com.ffpp.geoip", attributes: .concurrent)

    private init() {}

    /// Resolves location for a given server address and name
    public func resolveLocation(address: String, name: String) async -> GeoLocation? {
        let cleanHost = address.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Check in-memory cache
        var cached: GeoLocation?
        queue.sync { cached = self.cache[cleanHost] }
        if let cached = cached { return cached }

        // 2. Fast heuristic from server name (flags or country names)
        if let fromName = parseLocationFromText(name) {
            queue.async(flags: .barrier) { self.cache[cleanHost] = fromName }
            return fromName
        }

        // 3. Network lookup via public GeoIP endpoint
        guard let url = URL(string: "http://ip-api.com/json/\(cleanHost)?fields=status,country,countryCode,city") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = dict["status"] as? String, status == "success",
               let cc = dict["countryCode"] as? String, !cc.isEmpty {
                let country = (dict["country"] as? String) ?? cc
                let city = dict["city"] as? String
                let flag = countryCodeToFlag(cc)
                let russianCountry = translateCountry(country, code: cc)

                let loc = GeoLocation(
                    countryCode: cc,
                    countryName: russianCountry,
                    city: city,
                    flag: flag
                )

                queue.async(flags: .barrier) { self.cache[cleanHost] = loc }
                return loc
            }
        } catch {
            // Ignore network GeoIP failures
        }

        return nil
    }

    /// Converts 2-letter ISO country code to Flag Emoji
    public func countryCodeToFlag(_ countryCode: String) -> String {
        let base: UInt32 = 127397
        var flag = ""
        for v in countryCode.uppercased().unicodeScalars {
            if let scalar = UnicodeScalar(base + v.value) {
                flag.unicodeScalars.append(scalar)
            }
        }
        return flag.isEmpty ? "🌐" : flag
    }

    /// Fast extraction from node name
    private func parseLocationFromText(_ text: String) -> GeoLocation? {
        // Extract existing flag emoji from text if present
        for scalar in text.unicodeScalars {
            if (127462...127487).contains(scalar.value) {
                // Found regional indicator
                return GeoLocation(countryCode: "LOC", countryName: "", city: nil, flag: String(scalar))
            }
        }

        let lower = text.lowercased()
        let known: [(code: String, flag: String, name: String, matches: [String])] = [
            ("DE", "🇩🇪", "Германия", ["germany", "германия", "frankfurt", "де"]),
            ("NL", "🇳🇱", "Нидерланды", ["netherlands", "нидерланды", "amsterdam", "амстердам", "holland", "nl"]),
            ("FI", "🇫🇮", "Финляндия", ["finland", "финляндия", "helsinki", "хельсинки", "fi"]),
            ("US", "🇺🇸", "США", ["usa", "united states", "сша", "america", "us"]),
            ("RU", "🇷🇺", "Россия", ["russia", "россия", "moscow", "москва", "ru"]),
            ("SE", "🇸🇪", "Швеция", ["sweden", "швеция", "stockholm", "стокгольм", "se"]),
            ("PL", "🇵🇱", "Польша", ["poland", "польша", "warsaw", "варшава", "pl"]),
            ("FR", "🇫🇷", "Франция", ["france", "франция", "paris", "париж", "fr"]),
            ("GB", "🇬🇧", "Великобритания", ["uk", "united kingdom", "лондон", "london", "gb"]),
            ("KZ", "🇰🇿", "Казахстан", ["kazakhstan", "казахстан", "almaty", "алматы", "astana", "астана", "kz"]),
            ("TR", "🇹🇷", "Турция", ["turkey", "турция", "istanbul", "стамбул", "tr"]),
            ("JP", "🇯🇵", "Япония", ["japan", "япония", "tokyo", "токио", "jp"])
        ]

        for item in known {
            for m in item.matches {
                if lower.contains(m) {
                    return GeoLocation(countryCode: item.code, countryName: item.name, city: nil, flag: item.flag)
                }
            }
        }
        return nil
    }

    private func translateCountry(_ en: String, code: String) -> String {
        switch code.uppercased() {
        case "DE": return "Германия"
        case "NL": return "Нидерланды"
        case "FI": return "Финляндия"
        case "US": return "США"
        case "RU": return "Россия"
        case "SE": return "Швеция"
        case "PL": return "Польша"
        case "FR": return "Франция"
        case "GB": return "Великобритания"
        case "KZ": return "Казахстан"
        case "TR": return "Турция"
        case "JP": return "Япония"
        case "SG": return "Сингапур"
        case "CH": return "Швейцария"
        case "AT": return "Австрия"
        case "IT": return "Италия"
        case "ES": return "Испания"
        default: return en
        }
    }
}
