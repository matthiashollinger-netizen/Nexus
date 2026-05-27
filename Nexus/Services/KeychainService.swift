import Foundation
import Security

/// Manages the master password in the macOS Keychain.
struct KeychainService {
    private static let service = "com.hollinger.Nexus"
    private static let masterAccount = "NexusMasterPassword"

    // MARK: - Master Password

    /// Saves the master password to the local Keychain.
    /// - Parameter syncToiCloud: If true, syncs via iCloud Keychain across your Macs.
    static func saveMasterPassword(_ password: String, syncToiCloud: Bool = false) throws {
        let data = Data(password.utf8)

        // Delete any existing entry first (both local and iCloud)
        deleteMasterPassword()

        var query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        masterAccount,
            kSecValueData as String:          data,
            kSecAttrAccessible as String:     kSecAttrAccessibleWhenUnlocked,
            kSecAttrLabel as String:          "Nexus Master Password",
            kSecAttrComment as String:        "Automatically stored by Nexus"
        ]
        // Only set Synchronizable when explicitly requested (avoids macOS quirks)
        if syncToiCloud {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue!
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Loads the master password from the Keychain (local or iCloud).
    static func loadMasterPassword() -> String? {
        // kSecAttrSynchronizableAny matches both local and iCloud items
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        masterAccount,
            kSecReturnData as String:         true,
            kSecMatchLimit as String:         kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    /// Removes the master password from the Keychain.
    static func deleteMasterPassword() {
        // Delete all variants (local + iCloud)
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        masterAccount,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Whether a master password is currently stored in the Keychain.
    static var hasMasterPasswordInKeychain: Bool {
        loadMasterPassword() != nil
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return "Schlüsselbund-Fehler: \(msg)"
        }
    }
}
