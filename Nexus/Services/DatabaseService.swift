import Foundation
import CryptoKit
import CommonCrypto

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
        // Safety net: if we're about to overwrite a non-empty sessions file with an
        // EMPTY list, keep a copy first. This is the last line of defence against any
        // future "load-failed → empty in memory → overwrite good file" cascade.
        if sessions.isEmpty {
            let url = appSupportURL.appendingPathComponent("sessions.json")
            if let data = try? Data(contentsOf: url),
               let existing = try? JSONDecoder().decode([Session].self, from: data),
               !existing.isEmpty {
                let safety = appSupportURL.appendingPathComponent("sessions.beforeempty.json")
                try? data.write(to: safety, options: .atomic)
            }
        }
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
    //
    // Two on-disk formats, distinguished by a 4-byte magic prefix:
    //   • V2 (current): "NXS2" + [12 nonce][32 salt][ciphertext][16 tag]
    //     — key = PBKDF2-SHA256(password, salt, 210k iterations). PBKDF2 is a proper
    //     password-stretching KDF; brute-forcing a weak master password is ~10^5×
    //     costlier than the old HKDF single round.
    //   • V1 (legacy): [12 nonce][32 salt][ciphertext][16 tag] — key = HKDF-SHA256.
    // Legacy blobs are still decrypted and transparently upgraded to V2 on next read.

    func loadCredentials(masterPassword: String) throws -> [Credential] {
        let url = appSupportURL.appendingPathComponent("credentials.enc")
        guard let raw = try? Data(contentsOf: url), raw.count > 44 else { return [] }

        let (decrypted, wasLegacy) = try decryptBlob(raw, password: masterPassword)
        let credentials = try JSONDecoder().decode([Credential].self, from: decrypted)

        // Transparently migrate an old HKDF store to PBKDF2 on first successful read.
        if wasLegacy {
            try? saveCredentials(credentials, masterPassword: masterPassword)
        }
        return credentials
    }

    func saveCredentials(_ credentials: [Credential], masterPassword: String) throws {
        let url = appSupportURL.appendingPathComponent("credentials.enc")
        let json = try JSONEncoder().encode(credentials)
        let out  = try encryptBlob(json, password: masterPassword)
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
        let out  = try encryptBlob(json, password: masterPassword)
        try out.write(to: url)
    }

    func importDatabase(from url: URL, masterPassword: String) throws {
        let raw = try Data(contentsOf: url)
        guard raw.count > 44 else { throw DBError.invalidFormat }
        // Accepts both new (PBKDF2) and older (HKDF) export bundles.
        let (decrypted, _) = try decryptBlob(raw, password: masterPassword)
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
        guard let data = try? Data(contentsOf: url) else { return nil }   // file missing → nil
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // The file EXISTS but could not be decoded. With the tolerant model
            // decoders this should never happen for a schema change — but if it ever
            // does (genuinely corrupt JSON), preserve a copy so the data is not lost,
            // then return nil. We do NOT want the caller's `?? []` to silently lead to
            // overwriting the original (the v2.2.0 data-loss mechanism).
            preserveCorruptCopy(of: url)
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to filename: String) {
        let url = appSupportURL.appendingPathComponent(filename)
        guard let data = try? JSONEncoder().encode(value) else { return }
        // .atomic = write to a temp file, then rename — never leaves a half-written
        // file even if the app crashes mid-write.
        try? data.write(to: url, options: .atomic)
    }

    /// Copies a file that failed to decode to `<name>.corrupt-<timestamp>` so the user
    /// can recover it manually. Best-effort, never throws.
    private func preserveCorruptCopy(of url: URL) {
        let stamp = Self.timestampFormatter.string(from: Date())
        let dest = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
        try? FileManager.default.copyItem(at: url, to: dest)
    }

    // MARK: - Versioned blob crypto

    /// 4-byte magic marking the PBKDF2 (V2) format. A legacy V1 blob starts with a
    /// random AES-GCM nonce instead, so a collision is ~2^-32 (negligible).
    private static let magicV2 = Data("NXS2".utf8)
    /// PBKDF2-SHA256 work factor (OWASP-recommended floor for 2023+).
    private static let pbkdf2Iterations = 210_000

    /// Encrypts `plaintext` as a V2 blob (magic + nonce + salt + ciphertext + tag),
    /// keyed with PBKDF2-SHA256 over a fresh 32-byte salt.
    func encryptBlob(_ plaintext: Data, password: String) throws -> Data {
        let salt = Data(randomBytes(32))
        let key  = try deriveKeyPBKDF2(password: password, salt: salt)
        let box  = try AES.GCM.seal(plaintext, using: key)
        var out = Data()
        out.append(Self.magicV2)          // 4 bytes
        out.append(contentsOf: box.nonce) // 12 bytes
        out.append(salt)                  // 32 bytes
        out.append(box.ciphertext)
        out.append(box.tag)               // 16 bytes
        return out
    }

    /// Decrypts a V2 (PBKDF2) or legacy V1 (HKDF) blob. Returns the plaintext and
    /// whether the input was the legacy format (so the caller can re-save as V2).
    func decryptBlob(_ raw: Data, password: String) throws -> (data: Data, legacy: Bool) {
        let magic = Self.magicV2
        if raw.count > magic.count + 44, raw.prefix(magic.count) == magic {
            let body  = raw.dropFirst(magic.count)
            let nonce = body.prefix(12)
            let salt  = body.dropFirst(12).prefix(32)
            let rest  = body.dropFirst(44)
            let key   = try deriveKeyPBKDF2(password: password, salt: salt)
            return (try gcmDecrypt(ciphertextAndTag: rest, key: key, nonce: nonce), false)
        }
        // Legacy V1: no magic, HKDF-derived key.
        guard raw.count > 44 else { throw DBError.invalidFormat }
        let nonce = raw.prefix(12)
        let salt  = raw.dropFirst(12).prefix(32)
        let rest  = raw.dropFirst(44)
        let key   = deriveKey(password: password, salt: salt)
        return (try gcmDecrypt(ciphertextAndTag: rest, key: key, nonce: nonce), true)
    }

    /// Legacy V1 key derivation (HKDF-SHA256). Kept only to decrypt pre-3.0.3 blobs.
    private func deriveKey(password: String, salt: some DataProtocol) -> SymmetricKey {
        let inputKey = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("NexusCredentialsV1".utf8),
            outputByteCount: 32
        )
    }

    /// V2 key derivation: PBKDF2-SHA256 (proper password-stretching KDF).
    private func deriveKeyPBKDF2(password: String, salt: some DataProtocol) throws -> SymmetricKey {
        let pwData   = Data(password.utf8)
        let saltData = Data(salt)
        var derived  = [UInt8](repeating: 0, count: 32)

        let status = derived.withUnsafeMutableBufferPointer { out -> Int32 in
            saltData.withUnsafeBytes { saltBuf in
                pwData.withUnsafeBytes { pwBuf in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwBuf.bindMemory(to: CChar.self).baseAddress, pwData.count,
                        saltBuf.bindMemory(to: UInt8.self).baseAddress, saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(Self.pbkdf2Iterations),
                        out.baseAddress, out.count
                    )
                }
            }
        }
        guard Int(status) == kCCSuccess else { throw DBError.decryptionFailed }
        return SymmetricKey(data: Data(derived))
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
