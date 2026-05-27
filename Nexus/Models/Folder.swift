import Foundation

struct Folder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var parentId: UUID? = nil
    var credentialId: UUID? = nil
    var isExpanded: Bool = true
    var sortOrder: Int = 0
}
