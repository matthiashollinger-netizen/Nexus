import Foundation

/// Manages SSH_ASKPASS integration for `/usr/bin/ssh` password authentication.
///
/// Design (v2.1.0): **no Keychain**. Earlier versions stored the session password
/// in a temporary Keychain slot, which triggered a macOS security prompt on every
/// connection. We now write a short-lived shell script (0600) that echoes the
/// password, point `SSH_ASKPASS` at it, and delete it the moment the session ends.
/// This is the same keychain-free mechanism `SFTPService` already uses.
///
/// Flow:
///   1. `prepare(password:token:)` writes the temp askpass script, returns env vars.
///   2. Pass those env vars to SwiftTerm's `startProcess(environment:)`.
///   3. `cleanup(token:)` deletes the script after the session ends.
///
/// Security trade-off (documented in SECURITY_AUDIT.md): the password lives briefly
/// in a 0600 temp file owned by the user, removed immediately on disconnect. This
/// avoids both the Keychain popup and any plaintext password in the process arg list.
enum NexusAskPassService {

    /// Tracks the temp script path per session token so cleanup can remove it.
    nonisolated(unsafe) private static var scriptPaths: [String: String] = [:]
    private static let lock = NSLock()

    // MARK: - Prepare

    /// Writes a temporary askpass script for `password` and returns the environment
    /// dictionary to inject into the ssh process. Returns nil if `password` is empty.
    static func prepare(password: String, token: String) -> [String: String]? {
        guard !password.isEmpty else { return nil }

        // Escape characters special inside a double-quoted shell string.
        let escaped = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$",  with: "\\$")
            .replacingOccurrences(of: "`",  with: "\\`")
        let script = "#!/bin/sh\nprintf '%s\\n' \"\(escaped)\"\n"

        // Created 0700 from the start (no world-readable window, symlink-safe).
        guard let path = SecureTempScript.write(script, prefix: "nexus_askpass") else {
            return nil
        }

        lock.lock()
        scriptPaths[token] = path
        lock.unlock()

        return [
            "SSH_ASKPASS":         path,
            "SSH_ASKPASS_REQUIRE": "force",
            "DISPLAY":             ":"   // required for SSH to invoke SSH_ASKPASS at all
        ]
    }

    // MARK: - Cleanup

    /// Deletes the temp askpass script associated with `token`. Safe to call twice.
    static func cleanup(token: String) {
        lock.lock()
        let path = scriptPaths.removeValue(forKey: token)
        lock.unlock()
        if let path {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
