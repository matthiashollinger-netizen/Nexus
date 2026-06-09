import Testing
import Foundation
@testable import Nexus

/// Verifies SFTP builds the same connection options as the SSH terminal — the fix
/// for "Authentication failed" on legacy switches and for the configured port.
struct SFTPArgumentTests {

    private func conn(port: Int = 2222, legacy: Bool = true, strict: Bool = false,
                      jump: JumpHost? = nil, key: String? = nil,
                      host: String = "192.168.90.6", user: String = "admin") -> SFTPConnection {
        SFTPConnection(
            host: host, port: port, username: user, password: "pw", keyPath: key,
            options: SSHConnectionOptions(useLegacyAlgorithms: legacy,
                                          strictHostKeyChecking: strict,
                                          connectTimeout: 10, jumpHost: jump)
        )
    }

    @Test func usesUppercasePortFlag() {
        let args = SFTPService.shared.buildArguments(conn(port: 2222))
        // sftp uses -P (uppercase); -p would be wrong (that's ssh).
        let pIndex = args.firstIndex(of: "-P")
        #expect(pIndex != nil)
        if let i = pIndex { #expect(args[i + 1] == "2222") }
        #expect(!args.contains("-p"))   // must NOT use lowercase -p
    }

    @Test func appliesLegacyAlgorithmsWhenEnabled() {
        let args = SFTPService.shared.buildArguments(conn(legacy: true))
        let joined = args.joined(separator: " ")
        #expect(joined.contains("KexAlgorithms=+diffie-hellman-group14-sha1"))
        #expect(joined.contains("HostKeyAlgorithms=+ssh-rsa"))
        #expect(joined.contains("PubkeyAcceptedAlgorithms=+ssh-rsa"))
    }

    @Test func omitsLegacyAlgorithmsWhenDisabled() {
        let args = SFTPService.shared.buildArguments(conn(legacy: false))
        #expect(!args.joined(separator: " ").contains("group14-sha1"))
    }

    @Test func bypassesHostKeyByDefault() {
        let args = SFTPService.shared.buildArguments(conn(strict: false))
        let joined = args.joined(separator: " ")
        #expect(joined.contains("StrictHostKeyChecking=no"))
        #expect(joined.contains("UserKnownHostsFile=/dev/null"))
    }

    @Test func respectsStrictHostKeyChecking() {
        let args = SFTPService.shared.buildArguments(conn(strict: true))
        #expect(!args.joined(separator: " ").contains("StrictHostKeyChecking=no"))
    }

    @Test func includesJumpHost() {
        let jh = JumpHost(host: "bastion.example", port: 22, username: "jump")
        let args = SFTPService.shared.buildArguments(conn(jump: jh))
        let jIndex = args.firstIndex(of: "-J")
        #expect(jIndex != nil)
        if let i = jIndex { #expect(args[i + 1] == "jump@bastion.example:22") }
    }

    @Test func includesKeyPath() {
        let args = SFTPService.shared.buildArguments(conn(key: "/tmp/id_rsa"))
        let iIndex = args.firstIndex(of: "-i")
        #expect(iIndex != nil)
        if let i = iIndex { #expect(args[i + 1] == "/tmp/id_rsa") }
    }

    @Test func destinationIsUserAtHost() {
        let args = SFTPService.shared.buildArguments(conn(host: "10.0.0.5", user: "root"))
        #expect(args.last == "root@10.0.0.5")
    }

    @Test func parsesUserAtHostInHostField() {
        // If the host field itself contains "user@host", it is split correctly.
        let c = conn(host: "admin@10.0.0.7", user: "")
        let args = SFTPService.shared.buildArguments(c)
        #expect(args.last == "admin@10.0.0.7")
        #expect(args.contains("-P"))
    }
}
