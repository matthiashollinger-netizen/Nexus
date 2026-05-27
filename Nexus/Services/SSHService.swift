import Foundation

/// Builds the argument list for the system `ssh` binary.
/// The actual PTY/process management is done by SwiftTerm's LocalTerminalView.
struct SSHArgumentBuilder {
    let host: String
    let port: Int
    let username: String
    let privateKeyPath: String?
    let useLegacyAlgorithms: Bool
    let strictHostKeyChecking: Bool

    func build() -> [String] {
        // If the user entered "user@host" in the host field, split it out
        var effectiveUser = username
        var effectiveHost = host
        if host.contains("@"), let atRange = host.range(of: "@", options: .backwards) {
            let parsedUser = String(host[..<atRange.lowerBound])
            let parsedHost = String(host[atRange.upperBound...])
            if effectiveUser.isEmpty { effectiveUser = parsedUser }
            effectiveHost = parsedHost
        }

        var args: [String] = []

        args += ["-p", "\(port)"]
        args += ["-o", "ConnectTimeout=10"]
        args += ["-o", "ServerAliveInterval=60"]

        if useLegacyAlgorithms {
            // Note: diffie-hellman-group1-sha1 was completely removed in OpenSSH 9
            // and cannot be re-enabled even with +. Only include algorithms that still
            // exist in the binary.
            args += [
                "-o", "KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1",
                "-o", "HostKeyAlgorithms=+ssh-rsa",
                "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa"
            ]
        }

        if !strictHostKeyChecking {
            args += ["-o", "StrictHostKeyChecking=no"]
        }

        if let keyPath = privateKeyPath, !keyPath.isEmpty {
            args += ["-i", keyPath]
        }

        // Build destination: prefer "user@host", fall back to host-only if no user
        if effectiveUser.isEmpty {
            args += [effectiveHost]
        } else {
            args += ["\(effectiveUser)@\(effectiveHost)"]
        }

        return args
    }

    /// Writes the private key string to a temp file and returns the path.
    static func writeTempPrivateKey(_ content: String) throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nexus_key_\(UUID().uuidString)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url.path
    }
}
