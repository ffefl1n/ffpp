import Foundation

public enum SubscriptionError: LocalizedError {
    case invalidURL
    case networkError(String)
    case invalidResponse(Int)
    case parsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный адрес ссылки подписки."
        case .networkError(let msg):
            return "Сетевая ошибка при загрузке: \(msg)"
        case .invalidResponse(let code):
            return "Сервер вернул ошибку HTTP \(code). Проверьте статус подписки или привязку HWID."
        case .parsingFailed(let msg):
            return "Не удалось разобрать серверы: \(msg)"
        }
    }
}

public final class HappSubscriptionService {
    public static let shared = HappSubscriptionService()
    private init() {}

    /// Normalizes URL, stripping custom `happ://` scheme wrappers if present.
    public func normalizeSubscriptionURL(_ rawURL: String) -> URL? {
        var clean = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle happ:// schema
        if clean.lowercased().hasPrefix("happ://") {
            let withoutPrefix = String(clean.dropFirst("happ://".count))
            if withoutPrefix.lowercased().hasPrefix("add/") {
                let target = String(withoutPrefix.dropFirst("add/".count))
                if let decoded = target.removingPercentEncoding,
                   let url = URL(string: decoded), url.scheme != nil {
                    return url
                }
                if let url = URL(string: target), url.scheme != nil {
                    return url
                }
            } else if let components = URLComponents(string: clean),
                      let queryItems = components.queryItems,
                      let urlParam = queryItems.first(where: { $0.name.lowercased() == "url" })?.value,
                      let parsed = URL(string: urlParam) {
                return parsed
            }
        }

        return URL(string: clean)
    }

    /// Fetches subscription with official Happ headers and device HWID.
    public func fetchSubscription(from rawURL: String, subscriptionId: UUID) async throws -> (servers: [ServerConfig], hwid: String) {
        guard let url = normalizeSubscriptionURL(rawURL) else {
            throw SubscriptionError.invalidURL
        }

        let hwid = KeychainHelper.shared.getOrCreateHWID()

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20.0

        // Strict Happ headers to bypass panel restrictions and bind HWID
        request.setValue("Happ/3.13.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) Mobile/15E148", forHTTPHeaderField: "User-Agent")
        request.setValue(hwid, forHTTPHeaderField: "X-Hwid")
        request.setValue("iOS", forHTTPHeaderField: "X-Device-Os")
        request.setValue("iPhone15,2", forHTTPHeaderField: "X-Device-Model")
        request.setValue("ru-RU", forHTTPHeaderField: "X-Device-Locale")
        request.setValue("3.13.0", forHTTPHeaderField: "X-App-Version")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SubscriptionError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw SubscriptionError.invalidResponse(httpResponse.statusCode)
        }

        // Decode content (either plain text or base64)
        guard let text = decodeContent(data: data) else {
            throw SubscriptionError.parsingFailed("Не удалось декодировать ответ сервера")
        }

        let servers = parseSubscriptionContent(text: text, subscriptionId: subscriptionId)
        if servers.isEmpty {
            throw SubscriptionError.parsingFailed("Подписка не содержит поддерживаемых VLESS-узлов")
        }

        return (servers, hwid)
    }

    private func decodeContent(data: Data) -> String? {
        if let directString = String(data: data, encoding: .utf8) {
            let trimmed = directString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("vless://") {
                return trimmed
            }
            // Check if base64 encoded
            if let decodedData = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]),
               let decodedString = String(data: decodedData, encoding: .utf8) {
                return decodedString
            }
            return trimmed
        }
        return nil
    }

    /// Parses server lines (vless://...) into ServerConfig items.
    public func parseSubscriptionContent(text: String, subscriptionId: UUID) -> [ServerConfig] {
        var results: [ServerConfig] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
                continue
            }
            if trimmed.hasPrefix("vless://") {
                if let config = parseVLESSLink(trimmed, subscriptionId: subscriptionId) {
                    results.append(config)
                }
            }
        }
        return results
    }

    /// Parses a single VLESS URI (e.g. vless://uuid@host:port?security=reality&sni=...#Name)
    public func parseVLESSLink(_ link: String, subscriptionId: UUID? = nil) -> ServerConfig? {
        guard let url = URL(string: link),
              let uuid = url.user,
              let host = url.host,
              let port = url.port else {
            return nil
        }

        var name = host
        if let fragment = url.fragment, let decodedName = fragment.removingPercentEncoding, !decodedName.isEmpty {
            name = decodedName
        }

        var security = "reality"
        var sni: String? = nil
        var fp: String? = "chrome"
        var pbk: String? = nil
        var sid: String? = nil
        var spx: String? = nil
        var flow: String? = nil
        var network = "tcp"
        var path: String? = nil
        var headerHost: String? = nil
        var serviceName: String? = nil

        if let components = URLComponents(string: link), let queryItems = components.queryItems {
            for item in queryItems {
                let key = item.name.lowercased()
                let value = item.value ?? ""
                switch key {
                case "security":
                    security = value.lowercased()
                case "sni":
                    sni = value
                case "fp":
                    fp = value
                case "pbk":
                    pbk = value
                case "sid":
                    sid = value
                case "spx":
                    spx = value
                case "flow":
                    flow = value
                case "type":
                    network = value.lowercased()
                case "path":
                    path = value
                case "host":
                    headerHost = value
                case "servicename":
                    serviceName = value
                default:
                    break
                }
            }
        }

        return ServerConfig(
            name: name,
            address: host,
            port: port,
            uuid: uuid,
            flow: flow,
            security: security,
            sni: sni ?? host,
            fingerprint: fp ?? "chrome",
            publicKey: pbk,
            shortId: sid,
            spiderX: spx,
            network: network,
            path: path,
            host: headerHost,
            serviceName: serviceName,
            subscriptionId: subscriptionId
        )
    }
}
