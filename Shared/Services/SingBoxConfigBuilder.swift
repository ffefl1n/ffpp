import Foundation

/// Generates valid sing-box JSON configuration for VLESS + Reality / TLS
public final class SingBoxConfigBuilder {
    public static let shared = SingBoxConfigBuilder()
    private init() {}

    public func buildJSON(for server: ServerConfig, settings: AppSettings) -> String? {
        var outboundDict: [String: Any] = [
            "type": "vless",
            "tag": "proxy",
            "server": server.address,
            "server_port": server.port,
            "uuid": server.uuid,
            "packet_encoding": "xudp"
        ]

        if let flow = server.flow, !flow.isEmpty {
            outboundDict["flow"] = flow
        }

        // TLS & Reality configuration
        if server.security.lowercased() == "reality" || server.security.lowercased() == "tls" {
            var tlsDict: [String: Any] = [
                "enabled": true,
                "server_name": server.sni ?? server.address,
                "utls": [
                    "enabled": true,
                    "fingerprint": server.fingerprint ?? "chrome"
                ]
            ]

            if server.security.lowercased() == "reality" {
                var realityDict: [String: Any] = [
                    "enabled": true,
                    "public_key": server.publicKey ?? ""
                ]
                if let shortId = server.shortId, !shortId.isEmpty {
                    realityDict["short_id"] = shortId
                }
                tlsDict["reality"] = realityDict
            }

            outboundDict["tls"] = tlsDict
        }

        // Transport (WS / gRPC)
        if server.network.lowercased() == "ws" {
            var wsDict: [String: Any] = ["type": "ws"]
            if let path = server.path, !path.isEmpty {
                wsDict["path"] = path
            }
            if let host = server.host, !host.isEmpty {
                wsDict["headers"] = ["Host": host]
            }
            outboundDict["transport"] = wsDict
        } else if server.network.lowercased() == "grpc" {
            var grpcDict: [String: Any] = ["type": "grpc"]
            if let serviceName = server.serviceName ?? server.path, !serviceName.isEmpty {
                grpcDict["service_name"] = serviceName
            }
            outboundDict["transport"] = grpcDict
        }

        // Direct outbound
        let directOutbound: [String: Any] = [
            "type": "direct",
            "tag": "direct"
        ]

        // Block outbound
        let blockOutbound: [String: Any] = [
            "type": "block",
            "tag": "block"
        ]

        // TUN Inbound
        let tunInbound: [String: Any] = [
            "type": "tun",
            "tag": "tun-in",
            "interface_name": "utun10",
            "mtu": settings.mtu,
            "inet4_address": "172.19.0.1/30",
            "auto_route": true,
            "strict_route": true,
            "stack": "mixed",
            "sniff": true,
            "sniff_override_destination": true
        ]

        // DNS Configuration
        let dnsDict: [String: Any] = [
            "servers": [
                [
                    "tag": "dns-remote",
                    "address": "https://\(settings.remoteDNS)/dns-query",
                    "address_resolver": "dns-direct",
                    "detour": "proxy"
                ],
                [
                    "tag": "dns-direct",
                    "address": "https://\(settings.directDNS)/dns-query",
                    "detour": "direct"
                ]
            ],
            "rules": [
                [
                    "outbound": "any",
                    "server": "dns-direct"
                ]
            ],
            "strategy": "prefer_ipv4"
        ]

        // Route rules
        var routeRules: [[String: Any]] = [
            [
                "protocol": "dns",
                "outbound": "dns-remote"
            ]
        ]

        if settings.bypassLAN {
            routeRules.append([
                "ip_is_private": true,
                "outbound": "direct"
            ])
        }

        let routeDict: [String: Any] = [
            "rules": routeRules,
            "auto_detect_interface": true
        ]

        let fullConfig: [String: Any] = [
            "log": [
                "level": "info",
                "timestamp": true
            ],
            "dns": dnsDict,
            "inbounds": [tunInbound],
            "outbounds": [outboundDict, directOutbound, blockOutbound],
            "route": routeDict
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: fullConfig, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }

        return String(data: jsonData, encoding: .utf8)
    }
}
