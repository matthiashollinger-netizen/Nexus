import Testing
import Foundation
@testable import Nexus

/// REAL integration tests: start the native servers and talk to them with the
/// system `tftp` / `curl` clients — exactly how a network device would.
@MainActor
struct NativeServerIntegrationTests {

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NexusSrv_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func run(_ launchPath: String, _ args: [String], cwd: URL? = nil,
                     stdin: String? = nil, timeout: TimeInterval = 10) -> (out: String, code: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let outPipe = Pipe(); p.standardOutput = outPipe; p.standardError = outPipe
        let inPipe = Pipe(); if stdin != nil { p.standardInput = inPipe }
        try? p.run()
        if let stdin { inPipe.fileHandleForWriting.write(Data(stdin.utf8)); try? inPipe.fileHandleForWriting.close() }
        // Simple timeout watchdog.
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate() }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", p.terminationStatus)
    }

    // MARK: - TFTP

    @Test func tftpServesAndReceivesFiles() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = "hello tftp from nexus \(UUID().uuidString)"
        try content.write(to: dir.appendingPathComponent("img.bin"), atomically: true, encoding: .utf8)

        let port = Int.random(in: 7000...9500)
        guard let server = NativeTFTPServer(rootDirectory: dir, port: port) else {
            Issue.record("TFTP init failed"); return
        }
        try server.start()
        defer { server.stop() }
        try await Task.sleep(nanoseconds: 400_000_000)

        // --- GET (device downloads from us) ---
        let outDir = try tempDir()
        defer { try? FileManager.default.removeItem(at: outDir) }
        let getCmds = "mode octet\nconnect 127.0.0.1 \(port)\nget img.bin\nquit\n"
        _ = run("/usr/bin/tftp", [], cwd: outDir, stdin: getCmds, timeout: 8)
        let fetched = try? String(contentsOf: outDir.appendingPathComponent("img.bin"), encoding: .utf8)
        #expect(fetched == content)

        // --- PUT (device uploads to us) ---
        let upDir = try tempDir()
        defer { try? FileManager.default.removeItem(at: upDir) }
        let upContent = "uploaded config \(UUID().uuidString)"
        try upContent.write(to: upDir.appendingPathComponent("up.cfg"), atomically: true, encoding: .utf8)
        let putCmds = "mode octet\nconnect 127.0.0.1 \(port)\nput up.cfg\nquit\n"
        _ = run("/usr/bin/tftp", [], cwd: upDir, stdin: putCmds, timeout: 8)
        try await Task.sleep(nanoseconds: 300_000_000)
        let stored = try? String(contentsOf: dir.appendingPathComponent("up.cfg"), encoding: .utf8)
        #expect(stored == upContent)
    }

    @Test func tftpBlocksPathTraversal() {
        let dir = (try? tempDir()) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let server = NativeTFTPServer(rootDirectory: dir, port: 7777)
        #expect(server?.resolveSafePath("../../etc/passwd") == nil)
        #expect(server?.resolveSafePath("img.bin") != nil)
    }

    // MARK: - FTP

    @Test func ftpServesAndReceivesFiles() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = "hello ftp from nexus \(UUID().uuidString)"
        try content.write(to: dir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let port = Int.random(in: 21000...23000)
        guard let server = NativeFTPServer(rootDirectory: dir, port: port) else {
            Issue.record("FTP init failed"); return
        }
        try server.start()
        defer { server.stop() }
        try await Task.sleep(nanoseconds: 400_000_000)

        // --- Download via curl (passive mode) ---
        let (out, _) = run("/usr/bin/curl",
                           ["-s", "--connect-timeout", "5", "ftp://127.0.0.1:\(port)/readme.txt"],
                           timeout: 10)
        #expect(out == content)

        // --- Upload via curl ---
        let upDir = try tempDir()
        defer { try? FileManager.default.removeItem(at: upDir) }
        let upFile = upDir.appendingPathComponent("upload.txt")
        let upContent = "ftp upload \(UUID().uuidString)"
        try upContent.write(to: upFile, atomically: true, encoding: .utf8)
        _ = run("/usr/bin/curl",
                ["-s", "--connect-timeout", "5", "-T", upFile.path, "ftp://127.0.0.1:\(port)/uploaded.txt"],
                timeout: 10)
        try await Task.sleep(nanoseconds: 300_000_000)
        let stored = try? String(contentsOf: dir.appendingPathComponent("uploaded.txt"), encoding: .utf8)
        #expect(stored == upContent)
    }

    // MARK: - HTTP (native)

    @Test func httpServesFile() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = "hello http \(UUID().uuidString)"
        try content.write(to: dir.appendingPathComponent("index.txt"), atomically: true, encoding: .utf8)

        let port = Int.random(in: 18000...20000)
        guard let server = NativeHTTPServer(rootDirectory: dir, port: port) else {
            Issue.record("HTTP init failed"); return
        }
        try server.start()
        defer { server.stop() }
        try await Task.sleep(nanoseconds: 300_000_000)

        let (out, _) = run("/usr/bin/curl",
                           ["-s", "--connect-timeout", "5", "http://127.0.0.1:\(port)/index.txt"],
                           timeout: 8)
        #expect(out == content)
    }
}
