import Foundation

public enum SubscriptionError: LocalizedError {
    case invalidURL
    case networkError(String)
    case invalidResponse(Int)
    case parsingFailed(String, rawPreview: String?)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный адрес ссылки подписки."
        case .networkError(let msg):
            return "Сетевая ошибка при загрузке: \(msg)"
        case .invalidResponse(let code):
            return "Сервер вернул HTTP \(code). Проверьте статус подписки или привязку HWID."
        case .parsingFailed(let msg, let rawPreview):
            if let preview = rawPreview, !preview.isEmpty {
                return "\(msg)\n\nОтвет сервера:\n\(preview.prefix(350))"
            }
            return msg
        }
    }
}

public final class HappSubscriptionService {
    public static let shared = HappSubscriptionService()
    public private(set) var lastRawResponse: String?

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

        // Cache raw response string for diagnostics
        let rawText = decodeString(from: data) ?? "<\(data.count) bytes binary data>"
        self.lastRawResponse = rawText

        let servers = parsePayload(data: data, subscriptionId: subscriptionId)
        if servers.isEmpty {
            let preview = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SubscriptionError.parsingFailed(
                "Узлы не найдены (получено \(data.count) байт).",
                rawPreview: preview.isEmpty ? nil : preview
            )
        }

        return (servers, hwid)
    }

    // MARK: - String Decoding Helper (UTF-8, Latin1, ASCII)
    private func decodeString(from data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .ascii) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        if let s = String(data: data, encoding: .windowsCP1251) { return s }
        return nil
    }

    // MARK: - Safe Base64 Helper (Supports standard & URL-safe with auto-padding)
    public func safeBase64Decode(_ input: String) -> Data? {
        var base64 = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        return Data(base64Encoded: base64, options: [.ignoreUnknownCharacters])
    }

    // MARK: - Universal Payload Parser
    public func parsePayload(data: Data, subscriptionId: UUID) -> [ServerConfig] {
        // 1. Direct JSON parse
        if let json = try? JSONSerialization.jsonObject(with: data, options: []),
           let servers = extractServersFromJSON(json, subscriptionId: subscriptionId), !servers.isEmpty {
            return servers
        }

        // 2. String conversion
        guard let rawString = decodeString(from: data)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return []
        }

        // 3. String as JSON
        if let stringData = rawString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: stringData, options: []),
           let servers = extractServersFromJSON(json, subscriptionId: subscriptionId), !servers.isEmpty {
            return servers
        }

        // 4. Try Base64 Decoding
        if let decodedData = safeBase64Decode(rawString) {
            // Check if base64 contains JSON
            if let json = try? JSONSerialization.jsonObject(with: decodedData, options: []),
               let servers = extractServersFromJSON(json, subscriptionId: subscriptionId), !servers.isEmpty {
                return servers
            }
            // Check if base64 contains URI lines
            if let decodedString = decodeString(from: decodedData) {
                let linesServers = parseURILines(decodedString, subscriptionId: subscriptionId)
                if !linesServers.isEmpty {
                    return linesServers
                }
            }
        }

        // 5. Plain URI lines
        return parseURILines(rawString, subscriptionId: subscriptionId)
    }

    // MARK: - Recursive JSON Server Extractor
    public func extractServersFromJSON(_ json: Any, subscriptionId: UUID) -> [ServerConfig]? {
        var collected: [ServerConfig] = []

        func traverse(_ node: Any) {
            if let dict = node as? [String: Any] {
                // Check if this dict itself is a server configuration
                if let config = parseSingleServerDict(dict, subscriptionId: subscriptionId) {
                    collected.append(config)
                    return
                }

                // Check known collection keys
                let candidateKeys = ["outbounds", "proxies", "servers", "nodes", "configs", "configurations", "items", "data", "links", "list"]
                for key in candidateKeys {
                    if let child = dict[key] {
                        traverse(child)
                    }
                }

                // If not found in known keys, traverse all child values
                if collected.isEmpty {
                    for (_, value) in dict {
                        if value is [String: Any] || value is [Any] {
                            traverse(value)
                        }
                    }
                }
            } else if let array = node as? [Any] {
                for element in array {
                    if let stringElem = element as? String {
                        if let config = parseAnyLink(stringElem, subscriptionId: subscriptionId) {
                            collected.append(config)
                        }
                    } else if let dictElem = element as? [String: Any] {
                        traverse(dictElem)
                    }
                }
            }
        }

        traverse(json)
        return collected.isEmpty ? nil : collected
    }

    // MARK: - Single Dict Parser (sing-box, Xray, Clash Meta, Remnawave)
    private func parseSingleServerDict(_ dict: [String: Any], subscriptionId: UUID) -> ServerConfig? {
        let tag = (dict["tag"] as? String) ??
                  (dict["name"] as? String) ??
                  (dict["ps"] as? String) ??
                  (dict["remark"] as? String) ?? "Proxy"

        let rawType = ((dict["type"] as? String) ?? (dict["protocol"] as? String) ?? "").lowercased()

        // 1. Check Xray vnext format (VLESS / VMess)
        if let settings = dict["settings"] as? [String: Any],
           let vnext = (settings["vnext"] as? [[String: Any]])?.first {
            let address = parseString(vnext["address"]) ?? parseString(dict["server"]) ?? ""
            let port = parsePort(vnext["port"]) ?? parsePort(dict["port"]) ?? 443
            let users = vnext["users"] as? [[String: Any]]
            let uuid = parseString(users?.first?["id"]) ?? parseString(users?.first?["uuid"]) ?? ""
            let flow = parseString(users?.first?["flow"])

            var security = "reality"
            var sni = address
            var pbk: String? = nil
            var sid: String? = nil
            var spx: String? = nil
            var network = "tcp"
            var path: String? = nil
            var host: String? = nil

            if let stream = dict["streamSettings"] as? [String: Any] {
                network = parseString(stream["network"]) ?? "tcp"
                security = parseString(stream["security"]) ?? "reality"

                if let reality = stream["realitySettings"] as? [String: Any] {
                    sni = parseString(reality["serverName"]) ?? address
                    pbk = parseString(reality["publicKey"])
                    sid = parseString(reality["shortId"])
                    spx = parseString(reality["spiderX"])
                } else if let tls = stream["tlsSettings"] as? [String: Any] {
                    sni = parseString(tls["serverName"]) ?? address
                }

                if let ws = stream["wsSettings"] as? [String: Any] {
                    path = parseString(ws["path"])
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

        // 2. Direct VLESS node (sing-box, Clash Meta, Remnawave)
        let isVLESS = (rawType == "vless") || (rawType.isEmpty && dict["uuid"] != nil)
        if isVLESS {
            let address = parseString(dict["server"]) ??
                          parseString(dict["address"]) ??
                          parseString(dict["host"]) ??
                          parseString(dict["ip"]) ?? ""

            let port = parsePort(dict["server_port"]) ??
                       parsePort(dict["port"]) ?? 443

            let uuid = parseString(dict["uuid"]) ??
                       parseString(dict["id"]) ??
                       parseString(dict["password"]) ?? ""

            if !address.isEmpty && !uuid.isEmpty {
                let flow = parseString(dict["flow"])
                var security = "none"
                var sni = address
                var pbk: String? = nil
                var sid: String? = nil
                var fp = "chrome"

                // Check sing-box TLS
                if let tls = dict["tls"] as? [String: Any], (tls["enabled"] as? Bool) ?? true {
                    security = "tls"
                    sni = parseString(tls["server_name"]) ?? address
                    if let utls = tls["utls"] as? [String: Any] {
                        fp = parseString(utls["fingerprint"]) ?? "chrome"
                    }
                    if let reality = tls["reality"] as? [String: Any], (reality["enabled"] as? Bool) ?? true {
                        security = "reality"
                        pbk = parseString(reality["public_key"])
                        sid = parseString(reality["short_id"])
                    }
                }

                // Check Clash Meta reality-opts
                if let realityOpts = dict["reality-opts"] as? [String: Any] {
                    security = "reality"
                    pbk = parseString(realityOpts["public-key"])
                    sid = parseString(realityOpts["short-id"])
                }
                if let sName = parseString(dict["servername"]) ?? parseString(dict["sni"]) {
                    sni = sName
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

        // 3. Hysteria 2 / Hy2 node
        let isHy2 = (rawType == "hysteria2" || rawType == "hy2")
        if isHy2 {
            let address = parseString(dict["server"]) ?? parseString(dict["address"]) ?? parseString(dict["host"]) ?? ""
            let port = parsePort(dict["server_port"]) ?? parsePort(dict["port"]) ?? 443
            let password = parseString(dict["password"]) ?? parseString(dict["auth"]) ?? ""

            var sni = address
            var insecure = false
            if let tls = dict["tls"] as? [String: Any] {
                sni = parseString(tls["server_name"]) ?? address
                insecure = (tls["insecure"] as? Bool) ?? false
            }
            if let sName = parseString(dict["sni"]) ?? parseString(dict["servername"]) {
                sni = sName
            }

            var obfsType: String? = nil
            var obfsPass: String? = nil
            if let obfs = dict["obfs"] as? [String: Any] {
                obfsType = parseString(obfs["type"])
                obfsPass = parseString(obfs["password"])
            } else if let obfsStr = parseString(dict["obfs"]) {
                obfsType = obfsStr
                obfsPass = parseString(dict["obfs-password"])
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

        // 4. Hysteria 1 node
        if rawType == "hysteria" {
            let address = parseString(dict["server"]) ?? parseString(dict["address"]) ?? ""
            let port = parsePort(dict["server_port"]) ?? parsePort(dict["port"]) ?? 443
            let auth = parseString(dict["auth_str"]) ?? parseString(dict["auth"]) ?? ""
            let sni = parseString((dict["tls"] as? [String: Any])?["server_name"]) ?? address

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

    // MARK: - Primitive Field Helpers
    private func parseString(_ val: Any?) -> String? {
        if let s = val as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = val as? NSNumber { return n.stringValue }
        return nil
    }

    private func parsePort(_ val: Any?) -> Int? {
        if let i = val as? Int { return i }
        if let n = val as? NSNumber { return n.intValue }
        if let s = val as? String, let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return i }
        return nil
    }

    // MARK: - URI Lines Parser
    public func parseURILines(_ text: String, subscriptionId: UUID) -> [ServerConfig] {
        var results: [ServerConfig] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
                continue
            }
            if let config = parseAnyLink(trimmed, subscriptionId: subscriptionId) {
                results.append(config)
            }
        }
        return results
    }

    public func parseAnyLink(_ link: String, subscriptionId: UUID) -> ServerConfig? {
        var target = link.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle happ:// wrapper
        if target.lowercased().hasPrefix("happ://add/") {
            let extracted = String(target.dropFirst("happ://add/".count))
            if let decoded = extracted.removingPercentEncoding {
                target = decoded
            }
        }

        if target.hasPrefix("vless://") {
            return parseVLESSLink(target, subscriptionId: subscriptionId)
        } else if target.hasPrefix("hysteria2://") || target.hasPrefix("hy2://") {
            return parseHysteria2Link(target, subscriptionId: subscriptionId)
        } else if target.hasPrefix("hysteria://") {
            return parseHysteria1Link(target, subscriptionId: subscriptionId)
        }
        return nil
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
