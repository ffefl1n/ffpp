import Foundation

public struct AppSettings: Codable, Equatable {
    public var bypassLAN: Bool
    public var remoteDNS: String
    public var directDNS: String
    public var mtu: Int
    public var activeServerId: UUID?
    public var autoConnectOnLaunch: Bool

    public init(
        bypassLAN: Bool = true,
        remoteDNS: String = "1.1.1.1",
        directDNS: String = "77.88.8.8",
        mtu: Int = 9000,
        activeServerId: UUID? = nil,
        autoConnectOnLaunch: Bool = false
    ) {
        self.bypassLAN = bypassLAN
        self.remoteDNS = remoteDNS
        self.directDNS = directDNS
        self.mtu = mtu
        self.activeServerId = activeServerId
        self.autoConnectOnLaunch = autoConnectOnLaunch
    }
}
