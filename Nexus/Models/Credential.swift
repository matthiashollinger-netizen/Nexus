import Foundation

struct Credential: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var username: String = ""
    var password: String = ""
    var privateKey: String = ""
    var privateKeyPassphrase: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// true = shown in password group picker (created manually in Password Manager)
    /// false = session-specific, managed implicitly, not shown in picker
    var isGroup: Bool = true
}
