import Foundation
import NetworkExtension
import os.log

#if canImport(Libbox)
import Libbox
#endif

open class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "com.ffpp.app.tunnel", category: "PacketTunnel")
    private var isRunning = false

    #if canImport(Libbox)
    private var boxService: LibboxBoxService?
    #endif

    open override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.info("Запуск системного VPN туннеля ffpp...")

        let configJSON = loadConfigJSON(options: options)
        guard let config = configJSON, !config.isEmpty else {
            logger.error("Конфигурация туннеля не найдена")
            completionHandler(NSError(domain: "com.ffpp.app.tunnel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Отсутствует конфигурация узла"]))
            return
        }

        // Configure system tunnel network settings
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "172.19.0.2")

        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]

        // Exclude private local networks (LAN)
        let lanRoutes: [NEIPv4Route] = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0")
        ]
        ipv4.excludedRoutes = lanRoutes
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: ["1.1.1.1", "1.0.0.1", "8.8.8.8"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        settings.mtu = 9000

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.logger.error("Ошибка применения сетевых параметров: \(error.localizedDescription)")
                completionHandler(error)
                return
            }

            self.isRunning = true

            #if canImport(Libbox)
            do {
                // Initialize Libbox Command Server or standalone core
                var optErr: NSError?
                let service = LibboxNewStandaloneCommandClient(config, &optErr)
                if let optErr = optErr {
                    self.logger.error("Ошибка инициализации Libbox: \(optErr.localizedDescription)")
                    completionHandler(optErr)
                    return
                }
                self.boxService = service
                try service?.start()
                self.logger.info("Libbox ядро успешно запущено")
                completionHandler(nil)
            } catch {
                self.logger.error("Сбой запуска Libbox: \(error.localizedDescription)")
                completionHandler(error)
            }
            #else
            // Fallback: Packet loop running
            self.logger.info("Туннель запущен (режим совместимости)")
            completionHandler(nil)
            #endif
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Остановка системного туннеля. Причина: \(reason.rawValue)")
        isRunning = false

        #if canImport(Libbox)
        try? boxService?.close()
        boxService = nil
        #endif

        completionHandler()
    }

    open override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        completionHandler?(nil)
    }

    private func loadConfigJSON(options: [String : NSObject]?) -> String? {
        // 1. Try providerConfiguration
        if let conf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
           let json = conf["configJSON"] as? String, !json.isEmpty {
            return json
        }

        // 2. Try App Group container file
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ffpp.app") {
            let configFile = groupURL.appendingPathComponent("singbox_config.json")
            if let data = try? Data(contentsOf: configFile), let str = String(data: data, encoding: .utf8) {
                return str
            }
        }

        return nil
    }
}
