import Testing
import Foundation
@testable import Nexus

/// Edge-case + real-world tests for the native servers and the SFTP auth pipeline.
@MainActor
struct ServerEdgeTests {

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NexusEdge_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Port validation (no crash on out-of-range)

    @Test func serversRejectInvalidPorts() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(NativeHTTPServer(rootDirectory: dir, port: 0) == nil)
        #expect(NativeHTTPServer(rootDirectory: dir, port: 70000) == nil)
        #expect(NativeTFTPServer(rootDirectory: dir, port: 0) == nil)
        #expect(NativeTFTPServer(rootDirectory: dir, port: 99999) == nil)
        #expect(NativeFTPServer(rootDirectory: dir, port: -1) == nil)
        #expect(NativeFTPServer(rootDirectory: dir, port: 70000) == nil)
    }

    // MARK: - Stop frees the port (can restart on the same port)

    @Test func httpStopFreesPort() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let port = Int.random(in: 18500...19500)

        let s1 = try #require(NativeHTTPServer(rootDirectory: dir, port: port))
        try s1.start()
        try await Task.sleep(nanoseconds: 250_000_000)
        s1.stop()
        try await Task.sleep(nanoseconds: 400_000_000)   // allow the OS to release the port

        // Re-binding the same port must succeed (port was freed).
        let s2 = try #require(NativeHTTPServer(rootDirectory: dir, port: port))
        try s2.start()
        defer { s2.stop() }
        try await Task.sleep(nanoseconds: 250_000_000)
        let url = URL(string: "http://127.0.0.1:\(port)/a.txt")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        #expect((resp as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "x")
    }

    // MARK: - REAL SFTP auth pipeline against the local sshd (if present)

    @Test func sftpWrongPasswordThrowsCleanly() async throws {
        // Only meaningful if a local SSH server is listening on :22.
        guard portOpen(22) else {
            // No local sshd → can't exercise the real pipeline; not a failure.
            return
        }
        let conn = SFTPConnection(
            host: "127.0.0.1", port: 22, username: "nexus_nonexistent_user",
            password: "definitely-the-wrong-password-\(UUID().uuidString)",
            keyPath: nil,
            options: SSHConnectionOptions(useLegacyAlgorithms: false,
                                          strictHostKeyChecking: false, connectTimeout: 6)
        )
        // Must THROW (auth fails) and must NOT hang or crash — proves the sftp process
        // + askpass env + error parsing run end-to-end against a real server.
        await #expect(throws: (any Error).self) {
            _ = try await SFTPService.shared.listHome(conn)
        }
    }

    private func portOpen(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }
}
