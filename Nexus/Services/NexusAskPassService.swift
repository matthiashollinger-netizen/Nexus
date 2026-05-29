import Foundation
import Security

/// Manages the SSH_ASKPASS integration.
///
/// Flow:
///   1. Call `prepare(password:token:)` before connecting — stores the password
///      in a temporary keychain slot.
///   2. Pass the env vars returned by `environment(token:askpassPath:)` to
///      SwiftTerm's `startProcess(executable:args:environment:)`.
///   3. SSH calls `nexus-askpass` when it needs the password; the script reads
///      from the same keychain slot.
///   4. Call `cleanup(token:)` after the session ends.
///
/// The keychain slot uses service = "com.hollinger.Nexus.askpass" and
/// account = the session UUID string, so multiple simultaneous sessions
/// each get their own isolated slot.

enum NexusAskPassService {

    private static let keychainService = "com.hollinger.Nexus.askpass"

    // MARK: - Keychain helpers

    static func storePassword(_ password: String, token: String) {
        let data = Data(password.utf8)
        // Delete any leftover first
        let delQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: token
        ]
        SecItemDelete(delQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        keychainService,
            kSecAttrAccount as String:        token,
            kSecValueData as String:          data,
            kSecAttrAccessible as String:     kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func cleanup(token: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: token
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Helper binary path

    /// Returns the path to the `nexus-askpass` script, deploying it from
    /// the app bundle to a writable location if necessary.
    static func askpassPath() -> String? {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Nexus")

        guard let supportDir else { return nil }

        let destURL = supportDir.appendingPathComponent("nexus-askpass")

        // Deploy from bundle if not yet present or if outdated
        if let bundleURL = Bundle.main.url(forResource: "nexus-askpass", withExtension: nil) {
            let needsDeploy: Bool
            if !FileManager.default.fileExists(atPath: destURL.path) {
                needsDeploy = true
            } else {
                // Redeploy if bundle version is newer (compare modification dates)
                let destMod = (try? FileManager.default.attributesOfItem(atPath: destURL.path))?[.modificationDate] as? Date ?? .distantPast
                let srcMod  = (try? FileManager.default.attributesOfItem(atPath: bundleURL.path))?[.modificationDate] as? Date ?? .distantPast
                needsDeploy = srcMod > destMod
            }

            if needsDeploy {
                try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.copyItem(at: bundleURL, to: destURL)
                // Set executable bit (0755)
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
            }
        }

        guard FileManager.default.isExecutableFile(atPath: destURL.path) else { return nil }
        return destURL.path
    }

    // MARK: - Environment builder

    /// Returns the process environment entries needed for SSH_ASKPASS.
    /// Pass these to `startProcess(environment:)` in SwiftTerm.
    ///
    /// - Returns: nil if the askpass helper is not available (skips ASKPASS setup).
    static func environment(token: String) -> [String: String]? {
        guard let path = askpassPath() else { return nil }
        return [
            "SSH_ASKPASS":         path,
            "SSH_ASKPASS_REQUIRE": "force",
            "NEXUS_ASKPASS_TOKEN": token,
            "DISPLAY":             ":"          // required for SSH_ASKPASS to activate
        ]
    }
}
