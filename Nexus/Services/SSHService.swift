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

    // Optional gateway features
    var jumpHost: JumpHost? = nil
    var portForwardings: [PortForwarding] = []
    var socks5Proxy: SOCKS5Config? = nil
    var connectTimeout: Int = 10

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
        args += ["-o", "ConnectTimeout=\(max(1, connectTimeout))"]
        args += ["-o", "ServerAliveInterval=60"]

        if useLegacyAlgorithms {
            args += [
                "-o", "KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1",
                "-o", "HostKeyAlgorithms=+ssh-rsa",
                "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa"
            ]
        }

        if !strictHostKeyChecking {
            args += ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
        }

        if let keyPath = privateKeyPath, !keyPath.isEmpty {
            args += ["-i", keyPath]
        }

        // ── Jump Host (ProxyJump) ─────────────────────────────────────────────
        if let j = jumpHost, !j.host.isEmpty {
            let jumpSpec: String
            if j.username.isEmpty {
                jumpSpec = "\(j.host):\(j.port)"
            } else {
                jumpSpec = "\(j.username)@\(j.host):\(j.port)"
            }
            args += ["-J", jumpSpec]
        }

        // ── Port Forwardings ──────────────────────────────────────────────────
        for fwd in portForwardings {
            switch fwd.type {
            case .local:
                // -L localPort:remoteHost:remotePort
                if fwd.localPort > 0 && !fwd.remoteHost.isEmpty && fwd.remotePort > 0 {
                    args += ["-L", "\(fwd.localPort):\(fwd.remoteHost):\(fwd.remotePort)"]
                }
            case .remote:
                // -R remotePort:localHost:localPort
                if fwd.localPort > 0 && !fwd.remoteHost.isEmpty && fwd.remotePort > 0 {
                    args += ["-R", "\(fwd.remotePort):\(fwd.remoteHost):\(fwd.localPort)"]
                }
            case .dynamic:
                // -D localPort (SOCKS5 proxy)
                if fwd.localPort > 0 {
                    args += ["-D", "\(fwd.localPort)"]
                }
            }
        }

        // ── SOCKS5 shortcut ───────────────────────────────────────────────────
        if let socks = socks5Proxy, socks.enabled, socks.localPort > 0 {
            args += ["-D", "\(socks.localPort)"]
        }

        // ── Destination ───────────────────────────────────────────────────────
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
