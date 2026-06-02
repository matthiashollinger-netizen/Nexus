import Foundation
import CryptoKit

final class DatabaseService {
    let appSupportURL: URL

    /// - Parameter rootDirectory: override the storage root (tests pass a temp dir
    ///   so they never touch the user's real data). Production passes nil.
    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            appSupportURL = rootDirectory
        } else {
            // Fallback chain instead of force-unwrap: app support → ~/Library/Application Support
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            appSupportURL = base.appendingPathComponent("Nexus", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
    }

    // MARK: - Sessions

    func loadSessions() -> [Session] {
        load([Session].self, from: "sessions.json") ?? []
    }

    func saveSessions(_ sessions: [Session]) {
        // Throttled snapshot of the PRE-save state before we overwrite it.
        createBackup(force: false)
        save(sessions, to: "sessions.json")
    }

    // MARK: - Folders

    func loadFolders() -> [Folder] {
        load([Folder].self, from: "folders.json") ?? []
    }

    func saveFolders(_ folders: [Folder]) {
        createBackup(force: false)
        save(folders, to: "folders.json")
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        load(AppSettings.self, from: "settings.json") ?? AppSettings()
    }

    func saveSettings(_ settings: AppSettings) {
        save(settings, to: "settings.json")
    }

    // MARK: - Credentials (AES-256-GCM encrypted)
    // File format: [12 nonce][32 salt][ciphertext][16 tag]
    // The salt at bytes 12-43 is the SAME salt used to derive the key via HKDF.

    func loadCredentials(masterPassword: String) throws -> [Credential] {
        let url = appSupportURL.appendingPathComponent("credentials.enc")
        guard let raw = try? Data(contentsOf: url), raw.count > 44 else { return [] }

        let nonce = raw[..<12]
        let salt  = raw[12..<44]   // salt used for key derivation
        let rest  = raw[44...]     // ciphertext + 16-byte tag

        let key = deriveKey(password: masterPassword, salt: salt)
        let decrypted = try gcmDecrypt(ciphertextAndTag: rest, key: key, nonce: nonce)
        return try JSONDecoder().decode([Credential].self, from: decrypted)
    }

    func saveCredentials(_ credentials: [Credential], masterPassword: String) throws {
        let url = appSupportURL.appendingPathComponent("credentials.enc")
        let json = try JSONEncoder().encode(credentials)
        let salt = Data(randomBytes(32))
        let key  = deriveKey(password: masterPassword, salt: salt)
        let box  = try AES.GCM.seal(json, using: key)
        // Store the SAME salt that was used to derive the key
        var out = Data()
        out.append(contentsOf: box.nonce)  // 12 bytes
        out.append(salt)                   // 32 bytes — matches key derivation above
        out.append(box.ciphertext)
        out.append(box.tag)                // 16 bytes
        try out.write(to: url, options: .atomic)
    }

    // MARK: - Export / Import

    func exportDatabase(to url: URL, masterPassword: String) throws {
        let credentials = try loadCredentials(masterPassword: masterPassword)
        let bundle = NexusExport(
            sessions: loadSessions(),
            folders: loadFolders(),
            credentials: credentials,
            settings: loadSettings(),
            exportDate: Date()
        )
        let json = try JSONEncoder().encode(bundle)
        let salt = Data(randomBytes(32))
        let key  = deriveKey(password: masterPassword, salt: salt)
        let box  = try AES.GCM.seal(json, using: key)
        var out = Data()
        out.append(contentsOf: box.nonce)
        out.append(salt)
        out.append(box.ciphertext)
        out.append(box.tag)
        try out.write(to: url)
    }

    func importDatabase(from url: URL, masterPassword: String) throws {
        let raw = try Data(contentsOf: url)
        guard raw.count > 44 else { throw DBError.invalidFormat }
        let nonce = raw[..<12]
        let salt  = raw[12..<44]
        let rest  = raw[44...]
        let key = deriveKey(password: masterPassword, salt: salt)
        let decrypted = try gcmDecrypt(ciphertextAndTag: rest, key: key, nonce: nonce)
        let bundle = try JSONDecoder().decode(NexusExport.self, from: decrypted)
        saveSessions(bundle.sessions)
        saveFolders(bundle.folders)
        saveSettings(bundle.settings)
        try saveCredentials(bundle.credentials, masterPassword: masterPassword)
    }

    // MARK: - Backups
    // A backup is a single timestamped JSON bundle that captures all data files,
    // including the encrypted credentials blob (base64) so no master password is
    // needed to take or keep a backup. Rolling window keeps the newest N backups.

    private var backupsURL: URL {
        let url = appSupportURL.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static let maxBackups = 15
    // Instance-level (not static): production uses a single shared db instance, and
    // per-instance state keeps tests hermetic under parallel execution.
    private var lastBackupAt: Date = .distantPast

    /// Creates a backup of the current data files. `force == false` throttles to at
    /// most one backup per `minInterval` seconds so frequent saves don't churn the ring.
    @discardableResult
    func createBackup(force: Bool = false, minInterval: TimeInterval = 300) -> URL? {
        if !force {
            let elapsed = Date().timeIntervalSince(lastBackupAt)
            if elapsed < minInterval { return nil }
        }

        // Don't back up an empty database (nothing to protect, avoids noise on first run)
        let sessions = loadSessions()
        let folders  = loadFolders()
        if sessions.isEmpty && folders.isEmpty { return nil }

        let credURL = appSupportURL.appendingPathComponent("credentials.enc")
        let credB64 = (try? Data(contentsOf: credURL))?.base64EncodedString()

        let bundle = BackupBundle(
            createdAt: Date(),
            sessions: sessions,
            folders: folders,
            settings: loadSettings(),
            credentialsEncBase64: credB64
        )

        guard let data = try? JSONEncoder().encode(bundle) else { return nil }

        // Short random suffix prevents collisions when two backups land in the same
        // second (timestamp has second granularity) — otherwise one would overwrite
        // the other and silently be lost.
        let stamp = Self.timestampFormatter.string(from: Date())
        let suffix = String(UUID().uuidString.prefix(6))
        let url = backupsURL.appendingPathComponent("backup_\(stamp)_\(suffix).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }

        lastBackupAt = Date()
        pruneBackups()
        return url
    }

    /// Returns all backups, newest first.
    func listBackups() -> [BackupInfo] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: backupsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []

        return urls
            .filter { $0.lastPathComponent.hasPrefix("backup_") && $0.pathExtension == "json" }
            .compactMap { url -> BackupInfo? in
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                // Read session/folder counts cheaply
                var sessionCount = 0
                if let data = try? Data(contentsOf: url),
                   let b = try? JSONDecoder().decode(BackupBundle.self, from: data) {
                    sessionCount = b.sessions.count
                }
                return BackupInfo(url: url, createdAt: modDate, sizeBytes: size, sessionCount: sessionCount)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Restores a backup: overwrites the live data files. The caller must reload
    /// the view model afterwards. Credentials are restored as the encrypted blob,
    /// so the existing master password continues to work.
    func restoreBackup(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let bundle = try JSONDecoder().decode(BackupBundle.self, from: data)

        // Back up the current state first so a restore is itself undoable.
        createBackup(force: true)

        saveSessions(bundle.sessions)
        saveFolders(bundle.folders)
        saveSettings(bundle.settings)

        let credURL = appSupportURL.appendingPathComponent("credentials.enc")
        if let b64 = bundle.credentialsEncBase64, let credData = Data(base64Encoded: b64) {
            try credData.write(to: credURL, options: .atomic)
        }
    }

    func deleteBackup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes the oldest backups beyond `maxBackups`.
    private func pruneBackups() {
        let backups = listBackups()  // newest first
        guard backups.count > Self.maxBackups else { return }
        for backup in backups[Self.maxBackups...] {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    // MARK: - Helpers

    private func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = appSupportURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to filename: String) {
        let url = appSupportURL.appendingPathComponent(filename)
        guard let data = try? JSONEncoder().encode(value) else { return }
        // .atomic = write to a temp file, then rename — never leaves a half-written
        // file even if the app crashes mid-write.
        try? data.write(to: url, options: .atomic)
    }

    private func deriveKey(password: String, salt: some DataProtocol) -> SymmetricKey {
        let inputKey = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("NexusCredentialsV1".utf8),
            outputByteCount: 32
        )
    }

    private func gcmDecrypt(ciphertextAndTag: some DataProtocol, key: SymmetricKey, nonce: some DataProtocol) throws -> Data {
        let bytes = Data(ciphertextAndTag)
        guard bytes.count >= 16 else { throw DBError.decryptionFailed }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: bytes.dropLast(16),
            tag: bytes.suffix(16)
        )
        do {
            return try AES.GCM.open(box, using: key)
        } catch {
            throw DBError.decryptionFailed
        }
    }

    private func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return bytes
    }
}

// @unchecked Sendable: pure value type — all properties are immutable Codable structs
struct NexusExport: Codable, @unchecked Sendable {
    let sessions: [Session]
    let folders: [Folder]
    let credentials: [Credential]
    let settings: AppSettings
    let exportDate: Date
}

/// A single backup bundle. Credentials are kept as the raw encrypted blob (base64)
/// so backups never need — and never expose — the master password.
struct BackupBundle: Codable {
    let createdAt: Date
    let sessions: [Session]
    let folders: [Folder]
    let settings: AppSettings
    let credentialsEncBase64: String?
}

/// Lightweight metadata about a backup file (for the management UI).
struct BackupInfo: Identifiable {
    var id: URL { url }
    let url: URL
    let createdAt: Date
    let sizeBytes: Int
    let sessionCount: Int
}

enum DBError: LocalizedError {
    case decryptionFailed
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .decryptionFailed: return String(localized: "error.wrong_password")
        case .invalidFormat: return String(localized: "error.invalid_format")
        }
    }
}
