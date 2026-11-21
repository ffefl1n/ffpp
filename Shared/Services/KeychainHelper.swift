import Foundation
import Security

/// Secure Keychain Helper that persists the device HWID across app reinstalls and updates.
public final class KeychainHelper {
    public static let shared = KeychainHelper()
    private let hwidKey = "com.ffpp.app.device_hwid"
    private let serviceName = "com.ffpp.app.security"

    private init() {}

    /// Retrieves the permanent HWID from Keychain, or creates, stores, and returns a new uppercase UUID.
    public func getOrCreateHWID() -> String {
        if let existing = readHWID() {
            return existing
        }
        let newHWID = UUID().uuidString.uppercased()
        saveHWID(newHWID)
        return newHWID
    }

    /// Reads the HWID from Keychain (falls back to UserDefaults if Keychain is temporarily inaccessible).
    public func readHWID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: hwidKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let hwid = String(data: data, encoding: .utf8), !hwid.isEmpty {
            return hwid
        }

        // Fallback to UserDefaults
        if let fallback = UserDefaults.standard.string(forKey: hwidKey), !fallback.isEmpty {
            // Restore to Keychain
            saveHWID(fallback)
            return fallback
        }
        return nil
    }

    /// Saves the HWID with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly so it remains accessible in background.
    @discardableResult
    public func saveHWID(_ hwid: String) -> Bool {
        guard let data = hwid.data(using: .utf8) else { return false }

        // Also duplicate in UserDefaults as safety fallback
        UserDefaults.standard.set(hwid, forKey: hwidKey)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: hwidKey
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: hwidKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Explicitly sets a custom HWID (e.g. if transferring from another device or Happ backup).
    public func setCustomHWID(_ hwid: String) {
        saveHWID(hwid.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
