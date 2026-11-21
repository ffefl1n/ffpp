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
    private var statusTimer: Timer?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnStatusDidChange(_:)),
            name: .NEVPNStatusDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnStatusDidChange(_:)),
            name: .NEVPNConfigurationChange,
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

    public func updateStatus() {
        guard let manager = providerManager else {
            if self.status != .disconnected {
                self.status = .disconnected
            }
            return
        }

        let newStatus: TunnelStatus
        switch manager.connection.status {
        case .connected:
            newStatus = .connected
            stopStatusPolling()
        case .connecting, .reasserting:
            newStatus = .connecting
        case .disconnecting:
            newStatus = .disconnecting
        case .disconnected:
            newStatus = .disconnected
            stopStatusPolling()
        case .invalid:
            newStatus = .invalid
            stopStatusPolling()
        @unknown default:
            newStatus = .disconnected
            stopStatusPolling()
        }

        if self.status != newStatus {
            self.status = newStatus
        }
    }

    private func startStatusPolling() {
        stopStatusPolling()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    private func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    public func connect(configJSON: String) {
        guard let manager = providerManager else {
            refreshManager()
            return
        }

        // Immediately update UI to connecting
        self.status = .connecting
        startStatusPolling()

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
                    self.status = .invalid
                    self.stopStatusPolling()
                    return
                }
                manager.loadFromPreferences { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.lastError = "Ошибка перезагрузки: \(error.localizedDescription)"
                            self.status = .invalid
                            self.stopStatusPolling()
                            return
                        }
                        do {
                            try manager.connection.startVPNTunnel(options: nil)
                            self.startStatusPolling()
                        } catch {
                            self.lastError = "Не удалось запустить туннель: \(error.localizedDescription)"
                            self.status = .invalid
                            self.stopStatusPolling()
                        }
                    }
                }
            }
        }
    }

    public func disconnect() {
        self.status = .disconnecting
        startStatusPolling()
        providerManager?.connection.stopVPNTunnel()
    }
}
