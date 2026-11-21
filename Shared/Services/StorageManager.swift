import Foundation

/// Complete Backup Data Container for export and import
public struct BackupPayload: Codable {
    public var version: Int
    public var timestamp: Date
    public var hwid: String
    public var subscriptions: [Subscription]
    public var servers: [ServerConfig]
    public var settings: AppSettings

    public init(
        version: Int = 1,
        timestamp: Date = Date(),
        hwid: String,
        subscriptions: [Subscription],
        servers: [ServerConfig],
        settings: AppSettings
    ) {
        self.version = version
        self.timestamp = timestamp
        self.hwid = hwid
        self.subscriptions = subscriptions
        self.servers = servers
        self.settings = settings
    }
}

/// Triple-redundant Storage Manager ensuring subscriptions and servers are never lost.
public final class StorageManager {
    public static let shared = StorageManager()

    public static let appGroupId = "group.com.ffpp.app"
    private let fileName = "ffpp_config_store.json"
    private let userDefaultsCacheKey = "com.ffpp.backup_payload_cache"

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - URLs
    private var appGroupDirectory: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId)
    }

    private var localAppSupportDirectory: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("ffpp", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }

    private var primaryFileURL: URL? {
        if let groupDir = appGroupDirectory {
            return groupDir.appendingPathComponent(fileName)
        }
        return localAppSupportDirectory.appendingPathComponent(fileName)
    }

    private var fallbackFileURL: URL {
        localAppSupportDirectory.appendingPathComponent(fileName)
    }

    // MARK: - Save Operations (Atomic & Redundant)
    public func save(subscriptions: [Subscription], servers: [ServerConfig], settings: AppSettings) {
        let hwid = KeychainHelper.shared.getOrCreateHWID()
        let payload = BackupPayload(
            hwid: hwid,
            subscriptions: subscriptions,
            servers: servers,
            settings: settings
        )

        guard let data = try? encoder.encode(payload) else {
            return
        }

        // 1. Write to App Group container if available (atomic write)
        if let primaryURL = primaryFileURL {
            try? data.write(to: primaryURL, options: .atomic)
        }

        // 2. Write to local Application Support directory (mirror copy)
        try? data.write(to: fallbackFileURL, options: .atomic)

        // 3. Mirror in UserDefaults (both group and standard) as instant in-memory fallback
        if let groupDefaults = UserDefaults(suiteName: Self.appGroupId) {
            groupDefaults.set(data, forKey: userDefaultsCacheKey)
        }
        UserDefaults.standard.set(data, forKey: userDefaultsCacheKey)
    }

    // MARK: - Load Operations (Fail-safe auto-recovery)
    public func load() -> (subscriptions: [Subscription], servers: [ServerConfig], settings: AppSettings) {
        // Step 1: Try primary file
        if let primaryURL = primaryFileURL,
           let data = try? Data(contentsOf: primaryURL),
           let payload = try? decoder.decode(BackupPayload.self, from: data) {
            return (payload.subscriptions, payload.servers, payload.settings)
        }

        // Step 2: Try fallback local Application Support file
        if let data = try? Data(contentsOf: fallbackFileURL),
           let payload = try? decoder.decode(BackupPayload.self, from: data) {
            // Restore primary file
            save(subscriptions: payload.subscriptions, servers: payload.servers, settings: payload.settings)
            return (payload.subscriptions, payload.servers, payload.settings)
        }

        // Step 3: Try UserDefaults cache (App Group or Standard)
        var cachedData: Data? = nil
        if let groupDefaults = UserDefaults(suiteName: Self.appGroupId) {
            cachedData = groupDefaults.data(forKey: userDefaultsCacheKey)
        }
        if cachedData == nil {
            cachedData = UserDefaults.standard.data(forKey: userDefaultsCacheKey)
        }

        if let data = cachedData,
           let payload = try? decoder.decode(BackupPayload.self, from: data) {
            // Restore files from UserDefaults backup
            save(subscriptions: payload.subscriptions, servers: payload.servers, settings: payload.settings)
            return (payload.subscriptions, payload.servers, payload.settings)
        }

        // Initial default state
        return ([], [], AppSettings())
    }

    // MARK: - Export Backup File
    public func createExportURL() -> URL? {
        let (subscriptions, servers, settings) = load()
        let hwid = KeychainHelper.shared.getOrCreateHWID()
        let payload = BackupPayload(
            hwid: hwid,
            subscriptions: subscriptions,
            servers: servers,
            settings: settings
        )

        guard let data = try? encoder.encode(payload) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateStr = formatter.string(from: Date())
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent("ffpp_backup_\(dateStr).json")

        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            return nil
        }
    }

    // MARK: - Import Backup File
    public func importBackup(from url: URL) -> Result<BackupPayload, Error> {
        do {
            let data = try Data(contentsOf: url)
            let payload = try decoder.decode(BackupPayload.self, from: data)
            // Save imported data
            save(subscriptions: payload.subscriptions, servers: payload.servers, settings: payload.settings)
            if !payload.hwid.isEmpty {
                KeychainHelper.shared.saveHWID(payload.hwid)
            }
            return .success(payload)
        } catch {
            return .failure(error)
        }
    }
}
