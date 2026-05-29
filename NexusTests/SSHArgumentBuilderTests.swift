import Testing
@testable import Nexus

struct SSHArgumentBuilderTests {

    // MARK: - Basic args

    @Test func basicArgs() {
        let builder = SSHArgumentBuilder(
            host: "192.168.1.1",
            port: 22,
            username: "admin",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        let args = builder.build()
        #expect(args.contains("-p"))
        #expect(args.contains("22"))
        #expect(args.contains("admin@192.168.1.1"))
        #expect(!args.contains("-i"))
    }

    @Test func basicArgsNoUser() {
        let builder = SSHArgumentBuilder(
            host: "10.0.0.1",
            port: 22,
            username: "",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        let args = builder.build()
        #expect(args.contains("10.0.0.1"))
        #expect(!args.contains("@"))
    }

    @Test func customPort() {
        let builder = SSHArgumentBuilder(
            host: "server.example.com",
            port: 2222,
            username: "root",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        let args = builder.build()
        #expect(args.contains("2222"))
    }

    // MARK: - Legacy algorithms

    @Test func legacyAlgorithms() {
        let builder = SSHArgumentBuilder(
            host: "router",
            port: 22,
            username: "admin",
            privateKeyPath: nil,
            useLegacyAlgorithms: true,
            strictHostKeyChecking: false
        )
        let args = builder.build()
        let joined = args.joined(separator: " ")
        #expect(joined.contains("diffie-hellman-group14-sha1"))
        #expect(joined.contains("ssh-rsa"))
        #expect(joined.contains("KexAlgorithms"))
    }

    @Test func noLegacyAlgorithms() {
        let builder = SSHArgumentBuilder(
            host: "router",
            port: 22,
            username: "admin",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        let args = builder.build()
        let joined = args.joined(separator: " ")
        #expect(!joined.contains("diffie-hellman-group14-sha1"))
    }

    // MARK: - Jump Host

    @Test func jumpHostArgs() {
        var builder = SSHArgumentBuilder(
            host: "192.168.2.100",
            port: 22,
            username: "root",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        builder.jumpHost = JumpHost(host: "jump.example.com", port: 22, username: "jumpuser")
        let args = builder.build()
        #expect(args.contains("-J"))
        let jumpIndex = args.firstIndex(of: "-J")!
        let jumpSpec = args[jumpIndex + 1]
        #expect(jumpSpec.contains("jump.example.com"))
        #expect(jumpSpec.contains("jumpuser"))
    }

    @Test func jumpHostNoUser() {
        var builder = SSHArgumentBuilder(
            host: "target.host",
            port: 22,
            username: "admin",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        builder.jumpHost = JumpHost(host: "bastion.host", port: 2222, username: "")
        let args = builder.build()
        #expect(args.contains("-J"))
        let idx = args.firstIndex(of: "-J")!
        #expect(args[idx + 1].contains("bastion.host"))
        #expect(args[idx + 1].contains("2222"))
        #expect(!args[idx + 1].contains("@"))
    }

    // MARK: - Port Forwarding Local

    @Test func portForwardingLocal() {
        var builder = SSHArgumentBuilder(
            host: "server",
            port: 22,
            username: "user",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        builder.portForwardings = [
            PortForwarding(type: .local, localPort: 8080, remoteHost: "internal.srv", remotePort: 80)
        ]
        let args = builder.build()
        #expect(args.contains("-L"))
        let idx = args.firstIndex(of: "-L")!
        #expect(args[idx + 1] == "8080:internal.srv:80")
    }

    // MARK: - Port Forwarding Remote

    @Test func portForwardingRemote() {
        var builder = SSHArgumentBuilder(
            host: "server",
            port: 22,
            username: "user",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        builder.portForwardings = [
            PortForwarding(type: .remote, localPort: 3000, remoteHost: "localhost", remotePort: 9090)
        ]
        let args = builder.build()
        #expect(args.contains("-R"))
        let idx = args.firstIndex(of: "-R")!
        // -R remotePort:localHost:localPort
        #expect(args[idx + 1] == "9090:localhost:3000")
    }

    // MARK: - SOCKS5

    @Test func socks5Args() {
        var builder = SSHArgumentBuilder(
            host: "server",
            port: 22,
            username: "user",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        builder.socks5Proxy = SOCKS5Config(enabled: true, localPort: 1080)
        let args = builder.build()
        #expect(args.contains("-D"))
        let idx = args.firstIndex(of: "-D")!
        #expect(args[idx + 1] == "1080")
    }

    @Test func socks5DisabledNotAdded() {
        var builder = SSHArgumentBuilder(
            host: "server",
            port: 22,
            username: "user",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        builder.socks5Proxy = SOCKS5Config(enabled: false, localPort: 1080)
        let args = builder.build()
        #expect(!args.contains("-D"))
    }

    // MARK: - Combined args

    @Test func combinedArgs() {
        var builder = SSHArgumentBuilder(
            host: "prod-server",
            port: 22,
            username: "deploy",
            privateKeyPath: "/home/user/.ssh/id_rsa",
            useLegacyAlgorithms: true,
            strictHostKeyChecking: false
        )
        builder.jumpHost = JumpHost(host: "bastion", port: 22, username: "bastion_user")
        builder.portForwardings = [
            PortForwarding(type: .local, localPort: 5432, remoteHost: "db.internal", remotePort: 5432)
        ]
        builder.socks5Proxy = SOCKS5Config(enabled: true, localPort: 9999)
        let args = builder.build()
        let joined = args.joined(separator: " ")

        // Check all features present
        #expect(args.contains("-i"))
        #expect(args.contains("/home/user/.ssh/id_rsa"))
        #expect(joined.contains("diffie-hellman-group14-sha1"))
        #expect(args.contains("-J"))
        #expect(args.contains("-L"))
        #expect(args.contains("-D"))
        #expect(args.last == "deploy@prod-server")
    }

    // MARK: - Strict host key checking

    @Test func strictHostKeyChecking() {
        let builder = SSHArgumentBuilder(
            host: "secure.host",
            port: 22,
            username: "user",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: true
        )
        let args = builder.build()
        let joined = args.joined(separator: " ")
        #expect(!joined.contains("StrictHostKeyChecking=no"))
    }

    @Test func noStrictHostKeyChecking() {
        let builder = SSHArgumentBuilder(
            host: "dev.host",
            port: 22,
            username: "user",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        let args = builder.build()
        let joined = args.joined(separator: " ")
        #expect(joined.contains("StrictHostKeyChecking=no"))
    }

    // MARK: - user@host parsing

    @Test func userAtHostParsing() {
        let builder = SSHArgumentBuilder(
            host: "admin@192.168.1.50",
            port: 22,
            username: "",
            privateKeyPath: nil,
            useLegacyAlgorithms: false,
            strictHostKeyChecking: false
        )
        let args = builder.build()
        // Should extract user from host field when username is empty
        #expect(args.last == "admin@192.168.1.50")
    }
}
