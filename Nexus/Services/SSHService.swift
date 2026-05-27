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
        var args: [String] = []

        args += ["-p", "\(port)"]
        args += ["-o", "ConnectTimeout=10"]

        if useLegacyAlgorithms {
            args += [
                "-o", "KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1,diffie-hellman-group1-sha1",
                "-o", "HostKeyAlgorithms=+ssh-rsa,ssh-dss",
                "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa,ssh-dss"
            ]
        }

        if !strictHostKeyChecking {
            args += ["-o", "StrictHostKeyChecking=no"]
        }

        if let keyPath = privateKeyPath, !keyPath.isEmpty {
            args += ["-i", keyPath]
        }

        args += ["\(username)@\(host)"]
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
