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
        let sync: CFBoolean = syncToiCloud ? kCFBooleanTrue! : kCFBooleanFalse!

        // Delete any existing entry first
        deleteMasterPassword()

        let query: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrService as String:         service,
            kSecAttrAccount as String:         masterAccount,
            kSecValueData as String:           data,
            kSecAttrSynchronizable as String:  sync,
            kSecAttrLabel as String:           "Nexus Master Password",
            kSecAttrComment as String:         "Automatically stored by Nexus"
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Loads the master password from the Keychain (local or iCloud).
    static func loadMasterPassword() -> String? {
        // Try local first, then iCloud
        for sync in [kCFBooleanFalse!, kCFBooleanTrue!] as [CFBoolean] {
            let query: [String: Any] = [
                kSecClass as String:               kSecClassGenericPassword,
                kSecAttrService as String:         service,
                kSecAttrAccount as String:         masterAccount,
                kSecReturnData as String:          true,
                kSecMatchLimit as String:          kSecMatchLimitOne,
                kSecAttrSynchronizable as String:  sync
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    /// Removes the master password from the Keychain.
    static func deleteMasterPassword() {
        for sync in [kCFBooleanFalse!, kCFBooleanTrue!] as [CFBoolean] {
            let query: [String: Any] = [
                kSecClass as String:              kSecClassGenericPassword,
                kSecAttrService as String:        service,
                kSecAttrAccount as String:        masterAccount,
                kSecAttrSynchronizable as String: sync
            ]
            SecItemDelete(query as CFDictionary)
        }
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
            return "Schlüsselbund-Fehler: \(SecCopyErrorMessageString(status, nil) as String? ?? "\(status)")"
        }
    }
}
