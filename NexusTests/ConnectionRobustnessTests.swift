import Testing
import Foundation
import Network
@testable import Nexus

/// Robustness tests for connection services: invalid ports must not crash, the SSH
/// askpass temp script must be created with 0700 and cleaned up, and serial port
/// enumeration must be safe.
@MainActor
struct ConnectionRobustnessTests {

    // MARK: - Telnet port validation (was a UInt16 overflow crash)

    @Test func telnetRejectsOutOfRangePort() {
        let svc = TelnetService()
        var failed = false
        svc.onStateChange = { state in if case .failed(_) = state { failed = true } }
        // 70000 > 65535 — the old `UInt16(port)` trapped here. Must surface failure.
        svc.connect(host: "127.0.0.1", port: 70000)
        #expect(failed)
        svc.disconnect()
    }

    @Test func telnetRejectsZeroPort() {
        let svc = TelnetService()
        var failed = false
        svc.onStateChange = { state in if case .failed(_) = state { failed = true } }
        svc.connect(host: "127.0.0.1", port: 0)
        #expect(failed)
        svc.disconnect()
    }

    // MARK: - Askpass lifecycle (Bereich 3)

    @Test func askpassCreatesScriptAndCleansUp() throws {
        let token = UUID().uuidString
        let env = NexusAskPassService.prepare(password: "S3cr3t!", token: token)
        #expect(env != nil)
        #expect(env?["SSH_ASKPASS_REQUIRE"] == "force")
        let path = try #require(env?["SSH_ASKPASS"])
        #expect(FileManager.default.fileExists(atPath: path))

        // Script must be 0700 (owner-only) so the password isn't world-readable.
        let perms = (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? Int
        #expect(perms == 0o700)

        // Cleanup must remove it (so a crashed/closed session leaves nothing behind).
        NexusAskPassService.cleanup(token: token)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func askpassEmptyPasswordReturnsNil() {
        #expect(NexusAskPassService.prepare(password: "", token: "t") == nil)
    }

    @Test func askpassPasswordNotInEnvValues() {
        // The password must live ONLY in the temp file, never in an env var (which
        // could leak via the process environment).
        let token = UUID().uuidString
        let env = NexusAskPassService.prepare(password: "leaky-pw-123", token: token)
        defer { NexusAskPassService.cleanup(token: token) }
        #expect(env?.values.contains("leaky-pw-123") == false)
    }

    // MARK: - Serial enumeration (Bereich 6)

    @Test func serialEnumerationIsSafe() {
        // May be empty (no serial devices on a CI Mac) — must not crash, and any
        // returned entry should be a /dev path.
        let ports = SerialService().availablePorts()
        for p in ports {
            #expect(p.hasPrefix("/dev/"))
        }
    }
}
