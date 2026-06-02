import Testing
import Foundation
@testable import Nexus

/// Tests for the native HTTP server — focuses on the security-critical path
/// resolution (no traversal outside the served root) and basic serving end-to-end.
struct NativeHTTPServerTests {

    /// Spins up the server on an ephemeral-ish port, serving a temp directory.
    private func makeServedDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NexusHTTP_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "hello nexus".write(to: dir.appendingPathComponent("index.txt"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func initRejectsInvalidPort() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        #expect(NativeHTTPServer(rootDirectory: dir, port: 0) == nil)
        #expect(NativeHTTPServer(rootDirectory: dir, port: -1) == nil)
        #expect(NativeHTTPServer(rootDirectory: dir, port: 8080) != nil)
    }

    @Test func servesAndStopsCleanly() async throws {
        let dir = try makeServedDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Pick a high port unlikely to collide.
        let port = Int.random(in: 49152...60000)
        guard let server = NativeHTTPServer(rootDirectory: dir, port: port) else {
            Issue.record("server init failed"); return
        }
        try server.start()
        defer { server.stop() }

        // Give the listener a moment to come up.
        try await Task.sleep(nanoseconds: 300_000_000)

        let url = URL(string: "http://127.0.0.1:\(port)/index.txt")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = response as? HTTPURLResponse
        #expect(http?.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "hello nexus")
    }

    @Test func blocksPathTraversal() async throws {
        let dir = try makeServedDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let port = Int.random(in: 49152...60000)
        guard let server = NativeHTTPServer(rootDirectory: dir, port: port) else {
            Issue.record("server init failed"); return
        }
        try server.start()
        defer { server.stop() }
        try await Task.sleep(nanoseconds: 300_000_000)

        // Attempt to escape the served root via ../ — must NOT return /etc/passwd.
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
        // Use a raw traversal path that bypasses URL normalization.
        request.url = URL(string: "http://127.0.0.1:\(port)/../../../../etc/passwd")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        // Either 403/404 — but never the contents of /etc/passwd.
        #expect(http?.statusCode != 200 || !(String(data: data, encoding: .utf8) ?? "").contains("root:"))
    }
}
