import Foundation

public struct Subscription: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var url: String
    public var lastUpdated: Date?
    public var serverCount: Int
    public var hwidUsed: String
    public var userAgentUsed: String
    public var autoUpdate: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        url: String,
        lastUpdated: Date? = nil,
        serverCount: Int = 0,
        hwidUsed: String = "",
        userAgentUsed: String = "Happ/3.13.0",
        autoUpdate: Bool = true
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.lastUpdated = lastUpdated
        self.serverCount = serverCount
        self.hwidUsed = hwidUsed
        self.userAgentUsed = userAgentUsed
        self.autoUpdate = autoUpdate
    }
}
