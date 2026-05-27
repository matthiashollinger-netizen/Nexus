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
}
