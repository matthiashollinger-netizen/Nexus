import Testing
import Foundation
@testable import Nexus

/// Regression tests for the v2.2.0 data-loss bug: synthesized Codable required every
/// non-optional key to be present, so older `sessions.json` files failed to decode
/// and sessions silently vanished. The tolerant decoder must never fail on missing keys.
@MainActor
@Suite(.serialized)
struct SessionPersistenceTests {

    private func makeTempDB() -> (DatabaseService, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NexusPersist_\(UUID().uuidString)", isDirectory: true)
        return (DatabaseService(rootDirectory: dir), dir)
    }

    // MARK: - The actual bug: legacy JSON missing new keys must still decode

    @Test func decodesLegacyJSONMissingNewFields() throws {
        // A session as written by an OLDER version: no connectTimeout, no
        // autoConnectOnLaunch, no themeId, etc. Synthesized Codable would throw here.
        let legacy = """
        [{
          "id":"11111111-1111-1111-1111-111111111111",
          "name":"Old Switch","host":"192.168.90.6","port":2222,"username":"admin",
          "connectionType":"SSH","description":"","tags":[],"sortOrder":0,
          "sshPrivateKeyPath":"","sshStrictHostKeyChecking":false,
          "serialPort":"","serialBaudRate":9600,"serialDataBits":8,
          "serialStopBits":"1","serialParity":"none","serialFlowControl":"none",
          "portForwardings":[],
          "rdpUsername":"","rdpDomain":"","rdpWidth":1920,"rdpHeight":1080,
          "rdpColorDepth":32,"rdpFullscreen":false,"rdpClipboardSharing":true,
          "rdpDriveRedirection":false
        }]
        """
        let sessions = try JSONDecoder().decode([Session].self, from: Data(legacy.utf8))
        #expect(sessions.count == 1)
        #expect(sessions[0].host == "192.168.90.6")
        #expect(sessions[0].port == 2222)
        // Missing keys fall back to their defaults instead of throwing:
        #expect(sessions[0].connectTimeout == 10)
        #expect(sessions[0].autoConnectOnLaunch == false)
        #expect(sessions[0].themeId == nil)
    }

    @Test func decodesMinimalJSON() throws {
        // The most extreme case: almost everything missing. Must still decode.
        let minimal = #"[{"name":"X","host":"h"}]"#
        let sessions = try JSONDecoder().decode([Session].self, from: Data(minimal.utf8))
        #expect(sessions.count == 1)
        #expect(sessions[0].host == "h")
        #expect(sessions[0].connectionType == .ssh)   // default
        #expect(sessions[0].port == 22)               // default
    }

    @Test func encodeDecodeRoundTripPreservesAllFields() throws {
        var s = Session()
        s.name = "Full"; s.host = "10.0.0.9"; s.port = 2222
        s.connectTimeout = 30; s.autoConnectOnLaunch = true
        s.jumpHost = JumpHost(host: "jump.example", port: 22, username: "j")
        s.portForwardings = [PortForwarding(type: .local, localPort: 8080, remoteHost: "x", remotePort: 80)]

        let data = try JSONEncoder().encode([s])
        let back = try JSONDecoder().decode([Session].self, from: data)
        #expect(back.first?.connectTimeout == 30)
        #expect(back.first?.autoConnectOnLaunch == true)
        #expect(back.first?.jumpHost?.host == "jump.example")
        #expect(back.first?.portForwardings.first?.localPort == 8080)
    }

    // MARK: - Backups must contain the real session count (> 0)

    @Test func backupContainsSessions() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        var a = Session(); a.name = "A"; a.host = "10.0.0.1"
        var b = Session(); b.name = "B"; b.host = "10.0.0.2"
        db.saveSessions([a, b])
        db.saveFolders([])

        let url = db.createBackup(force: true)
        #expect(url != nil)

        // The backup metadata must report the real count, not 0.
        let info = db.listBackups().first
        #expect(info?.sessionCount == 2)
    }

    @Test func saveLoadRoundTripSessionsAndFolders() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        var s = Session(); s.name = "Persisted"; s.host = "172.16.0.1"; s.port = 2222
        var f = Folder(); f.name = "Lab"
        db.saveSessions([s])
        db.saveFolders([f])

        #expect(db.loadSessions().first?.host == "172.16.0.1")
        #expect(db.loadSessions().first?.port == 2222)
        #expect(db.loadFolders().first?.name == "Lab")
    }

    // MARK: - Empty-overwrite safety net keeps a copy

    @Test func emptyOverwriteKeepsSafetyCopy() throws {
        let (db, dir) = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        var s = Session(); s.name = "Important"; s.host = "10.9.9.9"
        db.saveSessions([s])

        // Now overwrite with empty — the safety copy must preserve the old data.
        db.saveSessions([])
        let safety = dir.appendingPathComponent("sessions.beforeempty.json")
        #expect(FileManager.default.fileExists(atPath: safety.path))
        let preserved = try JSONDecoder().decode([Session].self, from: Data(contentsOf: safety))
        #expect(preserved.first?.host == "10.9.9.9")
    }
}
