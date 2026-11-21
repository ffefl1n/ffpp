import Foundation

public struct ServerConfig: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var address: String
    public var port: Int
    public var protocolType: String // "vless", "hysteria2", "hysteria"
    public var uuid: String
    public var password: String?
    public var flow: String?
    public var security: String // "reality", "tls", "none"
    public var sni: String?
    public var fingerprint: String?
    public var publicKey: String?
    public var shortId: String?
    public var spiderX: String?
    public var obfsType: String?
    public var obfsPassword: String?
    public var insecure: Bool
    public var ports: String?
    public var network: String
    public var path: String?
    public var host: String?
    public var serviceName: String?
    public var subscriptionId: UUID?
    public var pingMs: Int?
    public var lastTested: Date?

    // GeoIP & Location Fields
    public var countryCode: String?
    public var countryName: String?
    public var city: String?
    public var flagEmoji: String?

    public init(
        id: UUID = UUID(),
        name: String,
        address: String,
        port: Int,
        protocolType: String = "vless",
        uuid: String,
        password: String? = nil,
        flow: String? = nil,
        security: String = "reality",
        sni: String? = nil,
        fingerprint: String? = "chrome",
        publicKey: String? = nil,
        shortId: String? = nil,
        spiderX: String? = nil,
        obfsType: String? = nil,
        obfsPassword: String? = nil,
        insecure: Bool = false,
        ports: String? = nil,
        network: String = "tcp",
        path: String? = nil,
        host: String? = nil,
        serviceName: String? = nil,
        subscriptionId: UUID? = nil,
        pingMs: Int? = nil,
        lastTested: Date? = nil,
        countryCode: String? = nil,
        countryName: String? = nil,
        city: String? = nil,
        flagEmoji: String? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.protocolType = protocolType
        self.uuid = uuid
        self.password = password
        self.flow = flow
        self.security = security
        self.sni = sni
        self.fingerprint = fingerprint
        self.publicKey = publicKey
        self.shortId = shortId
        self.spiderX = spiderX
        self.obfsType = obfsType
        self.obfsPassword = obfsPassword
        self.insecure = insecure
        self.ports = ports
        self.network = network
        self.path = path
        self.host = host
        self.serviceName = serviceName
        self.subscriptionId = subscriptionId
        self.pingMs = pingMs
        self.lastTested = lastTested
        self.countryCode = countryCode
        self.countryName = countryName
        self.city = city
        self.flagEmoji = flagEmoji
    }
}
