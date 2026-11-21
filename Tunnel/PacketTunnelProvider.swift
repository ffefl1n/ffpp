import Foundation
import NetworkExtension
import os.log
import Libbox

open class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "com.ffpp.app.tunnel", category: "PacketTunnel")
    private var boxService: LibboxBoxService?
    private var platformInterface: PlatformInterface?

    open override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.info("Запуск системного VPN туннеля ffpp v1.0.1...")

        let configJSON = loadConfigJSON(options: options)
        guard let config = configJSON, !config.isEmpty else {
            logger.error("Конфигурация туннеля не найдена")
            completionHandler(NSError(domain: "com.ffpp.app.tunnel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Отсутствует конфигурация узла"]))
            return
        }

        // Setup working directories for Libbox
        let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ffpp.app")
        let basePath = groupURL?.path ?? NSTemporaryDirectory()
        let workingPath = (groupURL?.appendingPathComponent("singbox_work") ?? URL(fileURLWithPath: NSTemporaryDirectory())).path
        let tempPath = (groupURL?.appendingPathComponent("singbox_temp") ?? URL(fileURLWithPath: NSTemporaryDirectory())).path

        try? FileManager.default.createDirectory(atPath: workingPath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: tempPath, withIntermediateDirectories: true)

        let setupOpts = LibboxSetupOptions()
        setupOpts.basePath = basePath
        setupOpts.workingPath = workingPath
        setupOpts.tempPath = tempPath
        var setupError: NSError?
        LibboxSetup(setupOpts, &setupError)
        if let setupError = setupError {
            logger.warning("LibboxSetup warning: \(setupError.localizedDescription)")
        }

        let platform = PlatformInterface(tunnel: self)
        self.platformInterface = platform

        var serviceErr: NSError?
        let service = LibboxNewService(config, platform, &serviceErr)
        if let serviceErr = serviceErr {
            logger.error("LibboxNewService error: \(serviceErr.localizedDescription)")
            completionHandler(serviceErr)
            return
        }
        guard let s = service else {
            completionHandler(NSError(domain: "com.ffpp.app.tunnel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Libbox service"]))
            return
        }

        self.boxService = s
        do {
            try s.start()
            self.logger.info("Libbox core successfully started")
            completionHandler(nil)
        } catch {
            self.logger.error("Libbox start failed: \(error.localizedDescription)")
            completionHandler(error)
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Остановка системного туннеля. Причина: \(reason.rawValue)")
        try? boxService?.close()
        boxService = nil
        platformInterface = nil
        completionHandler()
    }

    open override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        completionHandler?(nil)
    }

    private func loadConfigJSON(options: [String : NSObject]?) -> String? {
        // 1. Try options passed to startVPNTunnel
        if let options = options, let json = options["configJSON"] as? String, !json.isEmpty {
            return json
        }

        // 2. Try providerConfiguration
        if let conf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
           let json = conf["configJSON"] as? String, !json.isEmpty {
            return json
        }

        // 3. Try App Group container file
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ffpp.app") {
            let configFile = groupURL.appendingPathComponent("singbox_config.json")
            if let data = try? Data(contentsOf: configFile), let str = String(data: data, encoding: .utf8), !str.isEmpty {
                return str
            }
        }

        return nil
    }
}
