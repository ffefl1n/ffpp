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
            return "Сервер вернул HTTP \(code). Проверьте статус подписки или привязку HWID."
        case .parsingFailed(let msg):
            return "Ошибка разбора подписки: \(msg)"
        }
    }
}

public final class HappSubscriptionService {
    public static let shared = HappSubscriptionService()
    private init() {}

    /// Normalizes URL, stripping custom `happ://` scheme wrappers if present.
    public func normalizeSubscriptionURL(_ rawURL: String) -> URL? {
        let clean = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)

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

    /// Fetches subscription with official Happ headers and physical device model & HWID.
    public func fetchSubscription(from rawURL: String, subscriptionId: UUID) async throws -> (servers: [ServerConfig], hwid: String) {
        guard let url = normalizeSubscriptionURL(rawURL) else {
            throw SubscriptionError.invalidURL
        }

        let hwid = KeychainHelper.shared.getOrCreateHWID()
        let deviceModel = DeviceHelper.modelIdentifier
        let userAgent = DeviceHelper.userAgent

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25.0

        // Strict Happ headers to bypass panel restrictions and bind HWID
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(hwid, forHTTPHeaderField: "X-Hwid")
        request.setValue("iOS", forHTTPHeaderField: "X-Device-Os")
        request.setValue(deviceModel, forHTTPHeaderField: "X-Device-Model")
        request.setValue("ru-RU", forHTTPHeaderField: "X-Device-Locale")
        request.setValue("3.13.0", forHTTPHeaderField: "X-App-Version")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
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

        let servers = parsePayload(data: data, subscriptionId: subscriptionId)
        if servers.isEmpty {
            throw SubscriptionError.parsingFailed("Не удалось обнаружить VLESS или Hysteria узлы в ответе подписки.")
        }

        return (servers, hwid)
    }

    // MARK: - Universal Payload Parser (JSON + PlainText + Base64)
    public func parsePayload(data: Data, subscriptionId: UUID) -> [ServerConfig] {
        // 1. Try direct JSON parsing
        if let directJSON = try? JSONSerialization.jsonObject(with: data, options: []),
           let servers = parseJSON(directJSON, subscriptionId: subscriptionId), !servers.isEmpty {
            return servers
        }

        // 2. Decode string content
        guard let rawString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return []
        }

        // Try parsing string as JSON
        if let stringData = rawString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: stringData, options: []),
           let servers = parseJSON(json, subscriptionId: subscriptionId), !servers.isEmpty {
            return servers
        }

        // 3. Try Base64 decoding
        if let decodedData = Data(base64Encoded: rawString, options: [.ignoreUnknownCharacters]) {
            // Check if base64 contains JSON
            if let base64JSON = try? JSONSerialization.jsonObject(with: decodedData, options: []),
               let servers = parseJSON(base64JSON, subscriptionId: subscriptionId), !servers.isEmpty {
                return servers
            }

            // Check if base64 contains URI lines
            if let decodedString = String(data: decodedData, encoding: .utf8) {
                let linesServers = parseURILines(decodedString, subscriptionId: subscriptionId)
                if !linesServers.isEmpty {
                    return linesServers
                }
            }
        }

        // 4. Fallback: Parse plain URI lines
        return parseURILines(rawString, subscriptionId: subscriptionId)
    }

    // MARK: - JSON Parser (Happ / sing-box / Xray / 3x-ui schemas)
    private func parseJSON(_ json: Any, subscriptionId: UUID) -> [ServerConfig]? {
        var results: [ServerConfig] = []

        // If root is Dict containing "outbounds" or "servers"
        if let dict = json as? [String: Any] {
            if let outbounds = dict["outbounds"] as? [[String: Any]] {
                for item in outbounds {
                    if let config = parseOutboundDict(item, subscriptionId: subscriptionId) {
                        results.append(config)
                    }
                }
            } else if let servers = dict["servers"] as? [[String: Any]] {
                for item in servers {
                    if let config = parseOutboundDict(item, subscriptionId: subscriptionId) {
                        results.append(config)
                    }
                }
            }
        } else if let array = json as? [[String: Any]] {
            for item in array {
                if let config = parseOutboundDict(item, subscriptionId: subscriptionId) {
                    results.append(config)
                }
            }
        }

        return results.isEmpty ? nil : results
    }

    private func parseOutboundDict(_ dict: [String: Any], subscriptionId: UUID) -> ServerConfig? {
        let tag = (dict["tag"] as? String) ?? (dict["name"] as? String) ?? "Proxy"
        let rawType = ((dict["type"] as? String) ?? (dict["protocol"] as? String) ?? "").lowercased()

        // 1. VLESS Outbound (Xray or sing-box schema)
        if rawType == "vless" {
            // Check Xray style: settings.vnext[0]
            if let settings = dict["settings"] as? [String: Any],
               let vnext = (settings["vnext"] as? [[String: Any]])?.first {
                let address = (vnext["address"] as? String) ?? ""
                let port = (vnext["port"] as? Int) ?? 443
                let users = vnext["users"] as? [[String: Any]]
                let uuid = (users?.first?["id"] as? String) ?? ""
                let flow = users?.first?["flow"] as? String

                var security = "reality"
                var sni = address
                var pbk: String? = nil
                var sid: String? = nil
                var spx: String? = nil
                var network = "tcp"
                var path: String? = nil
                var host: String? = nil

                if let stream = dict["streamSettings"] as? [String: Any] {
                    network = (stream["network"] as? String) ?? "tcp"
                    security = (stream["security"] as? String) ?? "reality"

                    if let reality = stream["realitySettings"] as? [String: Any] {
                        sni = (reality["serverName"] as? String) ?? address
                        pbk = reality["publicKey"] as? String
                        sid = reality["shortId"] as? String
                        spx = reality["spiderX"] as? String
                    } else if let tls = stream["tlsSettings"] as? [String: Any] {
                        sni = (tls["serverName"] as? String) ?? address
                    }

                    if let ws = stream["wsSettings"] as? [String: Any] {
                        path = ws["path"] as? String
                        if let headers = ws["headers"] as? [String: String] {
                            host = headers["Host"]
                        }
                    }
                }

                if !address.isEmpty && !uuid.isEmpty {
                    return ServerConfig(
                        name: tag,
                        address: address,
                        port: port,
                        protocolType: "vless",
                        uuid: uuid,
                        flow: flow,
                        security: security,
                        sni: sni,
                        publicKey: pbk,
                        shortId: sid,
                        spiderX: spx,
                        network: network,
                        path: path,
                        host: host,
                        subscriptionId: subscriptionId
                    )
                }
            }

            // Check sing-box style: server, server_port, uuid
            if let address = (dict["server"] as? String) ?? (dict["address"] as? String),
               let port = (dict["server_port"] as? Int) ?? (dict["port"] as? Int),
               let uuid = dict["uuid"] as? String {
                let flow = dict["flow"] as? String
                var security = "none"
                var sni = address
                var pbk: String? = nil
                var sid: String? = nil
                var fp = "chrome"

                if let tls = dict["tls"] as? [String: Any], (tls["enabled"] as? Bool) ?? true {
                    security = "tls"
                    sni = (tls["server_name"] as? String) ?? address
                    if let utls = tls["utls"] as? [String: Any] {
                        fp = (utls["fingerprint"] as? String) ?? "chrome"
                    }
                    if let reality = tls["reality"] as? [String: Any], (reality["enabled"] as? Bool) ?? true {
                        security = "reality"
                        pbk = reality["public_key"] as? String
                        sid = reality["short_id"] as? String
                    }
                }

                return ServerConfig(
                    name: tag,
                    address: address,
                    port: port,
                    protocolType: "vless",
                    uuid: uuid,
                    flow: flow,
                    security: security,
                    sni: sni,
                    fingerprint: fp,
                    publicKey: pbk,
                    shortId: sid,
                    subscriptionId: subscriptionId
                )
            }
        }

        // 2. Hysteria 2 / Hy2 Outbound
        if rawType == "hysteria2" || rawType == "hy2" {
            let address = (dict["server"] as? String) ?? (dict["address"] as? String) ?? ""
            let port = (dict["server_port"] as? Int) ?? (dict["port"] as? Int) ?? 443
            let password = (dict["password"] as? String) ?? (dict["auth"] as? String) ?? ""

            var sni = address
            var insecure = false
            if let tls = dict["tls"] as? [String: Any] {
                sni = (tls["server_name"] as? String) ?? address
                insecure = (tls["insecure"] as? Bool) ?? false
            }

            var obfsType: String? = nil
            var obfsPass: String? = nil
            if let obfs = dict["obfs"] as? [String: Any] {
                obfsType = obfs["type"] as? String
                obfsPass = obfs["password"] as? String
            }

            if !address.isEmpty && !password.isEmpty {
                return ServerConfig(
                    name: tag,
                    address: address,
                    port: port,
                    protocolType: "hysteria2",
                    uuid: password,
                    password: password,
                    security: "tls",
                    sni: sni,
                    obfsType: obfsType,
                    obfsPassword: obfsPass,
                    insecure: insecure,
                    network: "udp",
                    subscriptionId: subscriptionId
                )
            }
        }

        // 3. Hysteria 1 Outbound
        if rawType == "hysteria" {
            let address = (dict["server"] as? String) ?? (dict["address"] as? String) ?? ""
            let port = (dict["server_port"] as? Int) ?? (dict["port"] as? Int) ?? 443
            let auth = (dict["auth_str"] as? String) ?? (dict["auth"] as? String) ?? ""
            let sni = ((dict["tls"] as? [String: Any])?["server_name"] as? String) ?? address

            if !address.isEmpty {
                return ServerConfig(
                    name: tag,
                    address: address,
                    port: port,
                    protocolType: "hysteria",
                    uuid: auth,
                    password: auth,
                    security: "tls",
                    sni: sni,
                    network: "udp",
                    subscriptionId: subscriptionId
                )
            }
        }

        return nil
    }

    // MARK: - URI Lines Parser (vless://, hysteria2://, hy2://, hysteria://)
    public func parseURILines(_ text: String, subscriptionId: UUID) -> [ServerConfig] {
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
            } else if trimmed.hasPrefix("hysteria2://") || trimmed.hasPrefix("hy2://") {
                if let config = parseHysteria2Link(trimmed, subscriptionId: subscriptionId) {
                    results.append(config)
                }
            } else if trimmed.hasPrefix("hysteria://") {
                if let config = parseHysteria1Link(trimmed, subscriptionId: subscriptionId) {
                    results.append(config)
                }
            }
        }
        return results
    }

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
                case "security": security = value.lowercased()
                case "sni": sni = value
                case "fp": fp = value
                case "pbk": pbk = value
                case "sid": sid = value
                case "spx": spx = value
                case "flow": flow = value
                case "type": network = value.lowercased()
                case "path": path = value
                case "host": headerHost = value
                case "servicename": serviceName = value
                default: break
                }
            }
        }

        return ServerConfig(
            name: name,
            address: host,
            port: port,
            protocolType: "vless",
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

    public func parseHysteria2Link(_ link: String, subscriptionId: UUID? = nil) -> ServerConfig? {
        guard let url = URL(string: link),
              let host = url.host,
              let port = url.port else {
            return nil
        }

        let password = url.user ?? ""
        var name = host
        if let fragment = url.fragment, let decoded = fragment.removingPercentEncoding, !decoded.isEmpty {
            name = decoded
        }

        var sni = host
        var insecure = false
        var obfsType: String? = nil
        var obfsPassword: String? = nil

        if let components = URLComponents(string: link), let queryItems = components.queryItems {
            for item in queryItems {
                let key = item.name.lowercased()
                let value = item.value ?? ""
                switch key {
                case "sni": sni = value
                case "insecure": insecure = (value == "1" || value.lowercased() == "true")
                case "obfs": obfsType = value
                case "obfs-password": obfsPassword = value
                default: break
                }
            }
        }

        return ServerConfig(
            name: name,
            address: host,
            port: port,
            protocolType: "hysteria2",
            uuid: password,
            password: password,
            security: "tls",
            sni: sni,
            obfsType: obfsType,
            obfsPassword: obfsPassword,
            insecure: insecure,
            network: "udp",
            subscriptionId: subscriptionId
        )
    }

    public func parseHysteria1Link(_ link: String, subscriptionId: UUID? = nil) -> ServerConfig? {
        guard let url = URL(string: link),
              let host = url.host,
              let port = url.port else {
            return nil
        }

        var name = host
        if let fragment = url.fragment, let decoded = fragment.removingPercentEncoding, !decoded.isEmpty {
            name = decoded
        }

        var auth = ""
        var sni = host

        if let components = URLComponents(string: link), let queryItems = components.queryItems {
            for item in queryItems {
                let key = item.name.lowercased()
                let value = item.value ?? ""
                switch key {
                case "auth": auth = value
                case "peer", "sni": sni = value
                default: break
                }
            }
        }

        return ServerConfig(
            name: name,
            address: host,
            port: port,
            protocolType: "hysteria",
            uuid: auth,
            password: auth,
            security: "tls",
            sni: sni,
            network: "udp",
            subscriptionId: subscriptionId
        )
    }
}
