import Foundation
import NetworkExtension
import Combine

public enum TunnelStatus: String {
    case disconnected = "Отключено"
    case connecting = "Подключение..."
    case connected = "Подключено"
    case disconnecting = "Отключение..."
    case invalid = "Ошибка"
}

public final class VPNManager: ObservableObject {
    public static let shared = VPNManager()

    @Published public private(set) var status: TunnelStatus = .disconnected
    @Published public var lastError: String?

    private var providerManager: NETunnelProviderManager?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnStatusDidChange(_:)),
            name: .NEVPNStatusDidChange,
            object: nil
        )
        refreshManager()
    }

    public func refreshManager() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.lastError = "Ошибка загрузки VPN: \(error.localizedDescription)"
                    return
                }

                if let existing = managers?.first {
                    self.providerManager = existing
                } else {
                    let newManager = NETunnelProviderManager()
                    let proto = NETunnelProviderProtocol()
                    proto.providerBundleIdentifier = "com.ffpp.app.tunnel"
                    proto.serverAddress = "VLESS Reality"
                    newManager.protocolConfiguration = proto
                    newManager.localizedDescription = "ffpp VLESS"
                    newManager.isEnabled = true
                    self.providerManager = newManager
                }

                self.updateStatus()
            }
        }
    }

    @objc private func vpnStatusDidChange(_ notification: Notification) {
        DispatchQueue.main.async {
            self.updateStatus()
        }
    }

    private func updateStatus() {
        guard let manager = providerManager else {
            status = .disconnected
            return
        }
        switch manager.connection.status {
        case .connected:
            status = .connected
        case .connecting, .reasserting:
            status = .connecting
        case .disconnecting:
            status = .disconnecting
        case .disconnected:
            status = .disconnected
        case .invalid:
            status = .invalid
        @unknown default:
            status = .disconnected
        }
    }

    public func connect(configJSON: String) {
        guard let manager = providerManager else {
            refreshManager()
            return
        }

        manager.isEnabled = true
        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.ffpp.app.tunnel"
        proto.serverAddress = "VLESS Reality"
        proto.providerConfiguration = ["configJSON": configJSON]
        manager.protocolConfiguration = proto

        // Also write config to App Group file for reliability
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: StorageManager.appGroupId) {
            let configFile = groupURL.appendingPathComponent("singbox_config.json")
            try? configJSON.data(using: .utf8)?.write(to: configFile, options: .atomic)
        }

        manager.saveToPreferences { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.lastError = "Не удалось сохранить VPN: \(error.localizedDescription)"
                    return
                }
                manager.loadFromPreferences { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.lastError = "Ошибка перезагрузки: \(error.localizedDescription)"
                            return
                        }
                        do {
                            try manager.connection.startVPNTunnel(options: nil)
                        } catch {
                            self.lastError = "Не удалось запустить туннель: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    public func disconnect() {
        providerManager?.connection.stopVPNTunnel()
    }
}
