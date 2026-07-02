import Testing
import Foundation
import CryptoKit
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

    // MARK: - v3.0.3 PBKDF2 format + legacy migration

    /// New saves use the versioned PBKDF2 format (magic "NXS2" prefix).
    @Test func newSaveUsesV2Magic() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        try db.saveCredentials([sampleCredential()], masterPassword: "pw")
        let raw = try Data(contentsOf: dir.appendingPathComponent("credentials.enc"))
        #expect(raw.prefix(4) == Data("NXS2".utf8))
    }

    /// Writes a pre-3.0.3 HKDF (V1) blob, then verifies it still decrypts AND is
    /// transparently upgraded to the PBKDF2 (V2) format on read — no data loss.
    @Test func legacyHKDFBlobDecryptsAndMigrates() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        let creds = [sampleCredential("Legacy Switch"), sampleCredential("Old Router")]
        let password = "pre-3.0.3-master"

        // Reproduce the exact legacy format: [12 nonce][32 salt][ct][16 tag], HKDF key.
        let legacyBlob = try Self.makeLegacyV1Blob(creds, password: password)
        #expect(legacyBlob.prefix(4) != Data("NXS2".utf8))   // sanity: not V2
        let url = dir.appendingPathComponent("credentials.enc")
        try legacyBlob.write(to: url)

        // Reading must decrypt the old blob correctly...
        let loaded = try db.loadCredentials(masterPassword: password)
        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.name == "Legacy Switch" })
        #expect(loaded.first?.password == "S3cr3t!Pa$$w0rd")

        // ...and upgrade the on-disk file to V2 in place.
        let upgraded = try Data(contentsOf: url)
        #expect(upgraded.prefix(4) == Data("NXS2".utf8))

        // The upgraded file still round-trips with the same password.
        let reloaded = try db.loadCredentials(masterPassword: password)
        #expect(reloaded.count == 2)
    }

    /// Builds a legacy V1 blob the way pre-3.0.3 `saveCredentials` did (HKDF-SHA256).
    private static func makeLegacyV1Blob(_ creds: [Credential], password: String) throws -> Data {
        let json = try JSONEncoder().encode(creds)
        let salt = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(password.utf8)),
            salt: salt,
            info: Data("NexusCredentialsV1".utf8),
            outputByteCount: 32
        )
        let box = try AES.GCM.seal(json, using: key)
        var out = Data()
        out.append(contentsOf: box.nonce)  // 12
        out.append(salt)                   // 32
        out.append(box.ciphertext)
        out.append(box.tag)                // 16
        return out
    }
}
