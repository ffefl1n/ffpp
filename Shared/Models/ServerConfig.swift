import Foundation

public struct ServerConfig: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var address: String
    public var port: Int
    public var uuid: String
    public var flow: String?
    public var security: String // "reality", "tls", "none"
    public var sni: String?
    public var fingerprint: String? // e.g. "chrome"
    public var publicKey: String? // pbk for Reality
    public var shortId: String? // sid for Reality
    public var spiderX: String? // spx for Reality
    public var network: String // "tcp", "ws", "grpc"
    public var path: String?
    public var host: String?
    public var serviceName: String?
    public var subscriptionId: UUID?
    public var pingMs: Int?
    public var lastTested: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        address: String,
        port: Int,
        uuid: String,
        flow: String? = nil,
        security: String = "reality",
        sni: String? = nil,
        fingerprint: String? = "chrome",
        publicKey: String? = nil,
        shortId: String? = nil,
        spiderX: String? = nil,
        network: String = "tcp",
        path: String? = nil,
        host: String? = nil,
        serviceName: String? = nil,
        subscriptionId: UUID? = nil,
        pingMs: Int? = nil,
        lastTested: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.uuid = uuid
        self.flow = flow
        self.security = security
        self.sni = sni
        self.fingerprint = fingerprint
        self.publicKey = publicKey
        self.shortId = shortId
        self.spiderX = spiderX
        self.network = network
        self.path = path
        self.host = host
        self.serviceName = serviceName
        self.subscriptionId = subscriptionId
        self.pingMs = pingMs
        self.lastTested = lastTested
    }
}
