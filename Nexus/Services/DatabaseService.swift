import Foundation
import CryptoKit

final class DatabaseService {
    let appSupportURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportURL = base.appendingPathComponent("Nexus", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
    }

    // MARK: - Sessions

    func loadSessions() -> [Session] {
        load([Session].self, from: "sessions.json") ?? []
    }

    func saveSessions(_ sessions: [Session]) {
        save(sessions, to: "sessions.json")
    }

    // MARK: - Folders

    func loadFolders() -> [Folder] {
        load([Folder].self, from: "folders.json") ?? []
    }

    func saveFolders(_ folders: [Folder]) {
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

    func loadCredentials(masterPassword: String) throws -> [Credential] {
        let url = appSupportURL.appendingPathComponent("credentials.enc")
        guard let raw = try? Data(contentsOf: url), raw.count > 44 else { return [] }

        let key = deriveKey(password: masterPassword, salt: raw[12..<44])
        let decrypted = try gcmDecrypt(data: raw[44...], key: key, nonce: raw[..<12])
        return try JSONDecoder().decode([Credential].self, from: decrypted)
    }

    func saveCredentials(_ credentials: [Credential], masterPassword: String) throws {
        let url = appSupportURL.appendingPathComponent("credentials.enc")
        let json = try JSONEncoder().encode(credentials)
        let salt = randomBytes(32)
        let key = deriveKey(password: masterPassword, salt: Data(salt))
        let encrypted = try gcmEncrypt(data: json, key: key)
        try encrypted.write(to: url, options: .atomic)
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
        let salt = randomBytes(32)
        let key = deriveKey(password: masterPassword, salt: Data(salt))
        let encrypted = try gcmEncrypt(data: json, key: key)
        try encrypted.write(to: url)
    }

    func importDatabase(from url: URL, masterPassword: String) throws {
        let raw = try Data(contentsOf: url)
        guard raw.count > 44 else { throw DBError.invalidFormat }
        let key = deriveKey(password: masterPassword, salt: raw[12..<44])
        let decrypted = try gcmDecrypt(data: raw[44...], key: key, nonce: raw[..<12])
        let bundle = try JSONDecoder().decode(NexusExport.self, from: decrypted)
        saveSessions(bundle.sessions)
        saveFolders(bundle.folders)
        saveSettings(bundle.settings)
        try saveCredentials(bundle.credentials, masterPassword: masterPassword)
    }

    // MARK: - Helpers

    private func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = appSupportURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to filename: String) {
        let url = appSupportURL.appendingPathComponent(filename)
        guard let data = try? JSONEncoder().encode(value) else { return }
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

    // Format: [12 nonce][32 salt][ciphertext][16 tag]
    private func gcmEncrypt(data: Data, key: SymmetricKey) throws -> Data {
        let salt = randomBytes(32)
        let box = try AES.GCM.seal(data, using: key)
        var out = Data()
        out.append(contentsOf: box.nonce)
        out.append(contentsOf: salt)
        out.append(box.ciphertext)
        out.append(box.tag)
        return out
    }

    private func gcmDecrypt(data: some DataProtocol, key: SymmetricKey, nonce: some DataProtocol) throws -> Data {
        let dataBytes = Data(data)
        guard dataBytes.count >= 16 else { throw DBError.decryptionFailed }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: dataBytes.dropLast(16),
            tag: dataBytes.suffix(16)
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

struct NexusExport: Codable {
    let sessions: [Session]
    let folders: [Folder]
    let credentials: [Credential]
    let settings: AppSettings
    let exportDate: Date
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
