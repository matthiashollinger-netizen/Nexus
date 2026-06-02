import Testing
import Foundation
@testable import Nexus

/// Security-critical tests for the AES-256-GCM credential encryption in
/// DatabaseService. Uses an injected temp directory so the user's real
/// credentials.enc is never touched.
@MainActor
@Suite(.serialized)
struct DatabaseCryptoTests {

    private func makeTempDB() -> (DatabaseService, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NexusCrypto_\(UUID().uuidString)", isDirectory: true)
        return (DatabaseService(rootDirectory: dir), dir)
    }

    private func sampleCredential(_ name: String = "Lab Switch") -> Credential {
        var c = Credential()
        c.name = name
        c.username = "admin"
        c.password = "S3cr3t!Pa$$w0rd"
        c.notes = "core switch"
        return c
    }

    @Test func encryptDecryptRoundTrip() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        let creds = [sampleCredential(), sampleCredential("Edge Router")]
        try db.saveCredentials(creds, masterPassword: "correct horse battery staple")

        let loaded = try db.loadCredentials(masterPassword: "correct horse battery staple")
        #expect(loaded.count == 2)
        #expect(loaded.first?.password == "S3cr3t!Pa$$w0rd")
        #expect(loaded.contains { $0.name == "Edge Router" })
    }

    @Test func wrongPasswordFails() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        try db.saveCredentials([sampleCredential()], masterPassword: "right-password")

        #expect(throws: (any Error).self) {
            _ = try db.loadCredentials(masterPassword: "wrong-password")
        }
    }

    @Test func tamperedCiphertextFails() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        try db.saveCredentials([sampleCredential()], masterPassword: "pw")

        // Flip a byte in the ciphertext region (past the 12-byte nonce + 32-byte salt).
        let url = dir.appendingPathComponent("credentials.enc")
        var raw = try Data(contentsOf: url)
        #expect(raw.count > 45)
        let idx = raw.count - 5   // somewhere in the ciphertext/tag
        raw[idx] ^= 0xFF
        try raw.write(to: url)

        // GCM authentication must reject the tampered data.
        #expect(throws: (any Error).self) {
            _ = try db.loadCredentials(masterPassword: "pw")
        }
    }

    @Test func differentSaltsProduceDifferentCiphertext() throws {
        let (db1, dir1) = makeTempDB()
        let (db2, dir2) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir1); try? FileManager.default.removeItem(at: dir2) }

        let creds = [sampleCredential()]
        try db1.saveCredentials(creds, masterPassword: "same-password")
        try db2.saveCredentials(creds, masterPassword: "same-password")

        let blob1 = try Data(contentsOf: dir1.appendingPathComponent("credentials.enc"))
        let blob2 = try Data(contentsOf: dir2.appendingPathComponent("credentials.enc"))

        // Same plaintext + same password but random salt/nonce → different ciphertext.
        #expect(blob1 != blob2)
    }

    @Test func emptyCredentialsRoundTrip() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        try db.saveCredentials([], masterPassword: "pw")
        let loaded = try db.loadCredentials(masterPassword: "pw")
        #expect(loaded.isEmpty)
    }

    @Test func loadingMissingFileReturnsEmpty() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        // No credentials.enc written yet — must return [] rather than throw.
        let loaded = try db.loadCredentials(masterPassword: "anything")
        #expect(loaded.isEmpty)
    }

    @Test func exportImportRoundTrip() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        var session = Session()
        session.name = "Exported"
        session.host = "198.51.100.7"
        db.saveSessions([session])
        try db.saveCredentials([sampleCredential()], masterPassword: "pw")

        let exportURL = dir.appendingPathComponent("export.nexus")
        try db.exportDatabase(to: exportURL, masterPassword: "pw")

        // Wipe and re-import into a second db.
        let (db2, dir2) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir2) }
        try db2.importDatabase(from: exportURL, masterPassword: "pw")

        #expect(db2.loadSessions().contains { $0.host == "198.51.100.7" })
        let creds = try db2.loadCredentials(masterPassword: "pw")
        #expect(creds.first?.username == "admin")
    }
}
