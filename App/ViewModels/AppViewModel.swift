import Foundation
import Combine
import SwiftUI
import Network

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var subscriptions: [Subscription] = []
    @Published public var servers: [ServerConfig] = []
    @Published public var settings: AppSettings = AppSettings()
    @Published public var activeServer: ServerConfig?
    @Published public var hwid: String = ""

    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var successMessage: String?
    @Published public var lastServerResponsePreview: String?

    public let vpnManager = VPNManager.shared
    private let storage = StorageManager.shared
    private let subscriptionService = HappSubscriptionService.shared

    public init() {
        loadData()
    }

    public func loadData() {
        let (subs, srvs, stgs) = storage.load()
        self.subscriptions = subs
        self.servers = srvs
        self.settings = stgs
        self.hwid = KeychainHelper.shared.getOrCreateHWID()

        if let activeId = stgs.activeServerId {
            self.activeServer = srvs.first(where: { $0.id == activeId })
        }
        if self.activeServer == nil, let first = srvs.first {
            self.activeServer = first
            self.settings.activeServerId = first.id
            saveData()
        }
    }

    public func saveData() {
        storage.save(subscriptions: subscriptions, servers: servers, settings: settings)
    }

    public func selectServer(_ server: ServerConfig) {
        activeServer = server
        settings.activeServerId = server.id
        saveData()

        if vpnManager.status == .connected {
            toggleVPN() // Reconnect with new server
        }
    }

    public func toggleVPN() {
        if vpnManager.status == .connected || vpnManager.status == .connecting {
            vpnManager.disconnect()
        } else {
            guard let server = activeServer else {
                errorMessage = "Выберите сервер для подключения"
                return
            }
            guard let configJSON = SingBoxConfigBuilder.shared.buildJSON(for: server, settings: settings) else {
                errorMessage = "Ошибка сборки конфигурации узла"
                return
            }
            vpnManager.connect(configJSON: configJSON)
        }
    }

    public func addSubscription(url: String, name: String? = nil) async {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else {
            errorMessage = "Ссылка не может быть пустой"
            return
        }

        isLoading = true
        errorMessage = nil
        let newSubId = UUID()
        let subName = (name?.isEmpty ?? true) ? "Подписка #\(subscriptions.count + 1)" : name!

        do {
            let (fetchedServers, usedHWID) = try await subscriptionService.fetchSubscription(from: cleanURL, subscriptionId: newSubId)
            let newSub = Subscription(
                id: newSubId,
                name: subName,
                url: cleanURL,
                lastUpdated: Date(),
                serverCount: fetchedServers.count,
                hwidUsed: usedHWID,
                userAgentUsed: DeviceHelper.userAgent
            )

            subscriptions.append(newSub)
            servers.append(contentsOf: fetchedServers)

            if activeServer == nil, let first = fetchedServers.first {
                activeServer = first
                settings.activeServerId = first.id
            }

            saveData()
            successMessage = "Успешно добавлено \(fetchedServers.count) узлов!"
        } catch {
            self.lastServerResponsePreview = subscriptionService.lastRawResponse
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    public func refreshSubscription(_ subscription: Subscription) async {
        isLoading = true
        errorMessage = nil

        do {
            let (fetchedServers, usedHWID) = try await subscriptionService.fetchSubscription(from: subscription.url, subscriptionId: subscription.id)

            // Remove existing servers belonging to this subscription
            servers.removeAll(where: { $0.subscriptionId == subscription.id })
            servers.append(contentsOf: fetchedServers)

            // Update subscription info
            if let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                subscriptions[index].lastUpdated = Date()
                subscriptions[index].serverCount = fetchedServers.count
                subscriptions[index].hwidUsed = usedHWID
                subscriptions[index].userAgentUsed = DeviceHelper.userAgent
            }

            // Restore active server if still exists or fallback to first
            if let activeId = settings.activeServerId, let match = servers.first(where: { $0.id == activeId }) {
                activeServer = match
            } else {
                activeServer = servers.first
                settings.activeServerId = activeServer?.id
            }

            saveData()
            successMessage = "Подписка «\(subscription.name)» обновлена: \(fetchedServers.count) узлов"
        } catch {
            self.lastServerResponsePreview = subscriptionService.lastRawResponse
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    public func deleteSubscription(_ subscription: Subscription) {
        subscriptions.removeAll(where: { $0.id == subscription.id })
        servers.removeAll(where: { $0.subscriptionId == subscription.id })

        if activeServer?.subscriptionId == subscription.id {
            activeServer = servers.first
            settings.activeServerId = activeServer?.id
        }
        saveData()
    }

    public func deleteServer(_ server: ServerConfig) {
        servers.removeAll(where: { $0.id == server.id })
        if activeServer?.id == server.id {
            activeServer = servers.first
            settings.activeServerId = activeServer?.id
        }
        saveData()
    }

    public func testPing(for server: ServerConfig) async {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }

        let start = CFAbsoluteTimeGetCurrent()
        let host = NWEndpoint.Host(server.address)
        let port = NWEndpoint.Port(rawValue: UInt16(server.port)) ?? 443

        let connection = NWConnection(host: host, port: port, using: .tcp)
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                let diff = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                DispatchQueue.main.async {
                    self.servers[index].pingMs = diff
                    self.servers[index].lastTested = Date()
                    if self.activeServer?.id == server.id {
                        self.activeServer?.pingMs = diff
                    }
                    self.saveData()
                }
                connection.cancel()
            } else if case .failed = state {
                DispatchQueue.main.async {
                    self.servers[index].pingMs = -1
                    if self.activeServer?.id == server.id {
                        self.activeServer?.pingMs = -1
                    }
                    self.saveData()
                }
                connection.cancel()
            }
        }
        connection.start(queue: .global())
    }

    public func testAllPings() async {
        for server in servers {
            await testPing(for: server)
        }
    }

    public func exportBackupURL() -> URL? {
        storage.createExportURL()
    }

    public func importBackup(from url: URL) {
        let result = storage.importBackup(from: url)
        switch result {
        case .success(let payload):
            self.subscriptions = payload.subscriptions
            self.servers = payload.servers
            self.settings = payload.settings
            self.hwid = payload.hwid
            self.activeServer = payload.servers.first(where: { $0.id == payload.settings.activeServerId }) ?? payload.servers.first
            successMessage = "Резервная копия успешно восстановлена!"
        case .failure(let err):
            errorMessage = "Ошибка импорта: \(err.localizedDescription)"
        }
    }
}
