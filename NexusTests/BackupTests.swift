import Testing
import Foundation
@testable import Nexus

/// Tests for the auto-backup system in DatabaseService.
/// Each test uses an isolated DatabaseService rooted in a unique temp directory by
/// overriding the Application Support path is not trivial, so these tests exercise
/// the pure backup-bundle round-trip and rolling logic through the public API on a
/// real (temporary) DatabaseService instance and clean up after themselves.
@MainActor
@Suite(.serialized)
struct BackupTests {

    /// A DatabaseService rooted in a fresh temp directory — never touches real data.
    private func makeTempDB() -> (DatabaseService, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NexusTest_\(UUID().uuidString)", isDirectory: true)
        return (DatabaseService(rootDirectory: dir), dir)
    }

    @Test func backupBundleRoundTrip() throws {
        var s = Session()
        s.name = "Backup Test Host"
        s.host = "192.0.2.10"
        let folder = Folder()

        let bundle = BackupBundle(
            createdAt: Date(),
            sessions: [s],
            folders: [folder],
            settings: AppSettings(),
            credentialsEncBase64: Data("dummy-encrypted".utf8).base64EncodedString()
        )

        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(BackupBundle.self, from: data)

        #expect(decoded.sessions.count == 1)
        #expect(decoded.sessions.first?.host == "192.0.2.10")
        #expect(decoded.folders.count == 1)
        #expect(decoded.credentialsEncBase64 != nil)

        // The encrypted credentials blob survives the round trip unchanged.
        let restored = Data(base64Encoded: decoded.credentialsEncBase64!)
        #expect(restored == Data("dummy-encrypted".utf8))
    }

    @Test func createAndListAndRestore() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Seed some data so createBackup has something to protect.
        var session = Session()
        session.name = "RestoreMe"
        session.host = "10.0.0.99"
        db.saveSessions([session])
        db.saveFolders([])

        // Force a backup and confirm it shows up.
        let backupURL = db.createBackup(force: true)
        #expect(backupURL != nil)

        // Compare by filename: NSTemporaryDirectory() is /var/... but
        // contentsOfDirectory resolves the symlink to /private/var/..., so the URL
        // objects differ in representation while pointing at the same file.
        let listed = db.listBackups()
        #expect(listed.contains { $0.url.lastPathComponent == backupURL?.lastPathComponent })

        // Mutate live data, then restore — the old host should come back.
        var changed = session
        changed.host = "172.16.0.1"
        db.saveSessions([changed])
        #expect(db.loadSessions().first?.host == "172.16.0.1")

        if let url = backupURL {
            try db.restoreBackup(from: url)
            #expect(db.loadSessions().contains { $0.host == "10.0.0.99" })
        }
    }

    @Test func emptyDatabaseIsNotBackedUp() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Fresh temp DB is empty — createBackup must refuse (avoids noise).
        let result = db.createBackup(force: true)
        #expect(result == nil)
        #expect(db.listBackups().isEmpty)
    }

    @Test func maxBackupsConstantIsSane() {
        // Guards against an accidental edit that would disable the rolling window.
        #expect(DatabaseService.maxBackups >= 5)
        #expect(DatabaseService.maxBackups <= 100)
    }
}
