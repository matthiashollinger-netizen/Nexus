import Foundation

struct Folder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var parentId: UUID? = nil
    var credentialId: UUID? = nil
    var isExpanded: Bool = true
    var sortOrder: Int = 0

    init() {}
}

// Tolerant decoder — see Session.swift for the full rationale. Missing keys fall
// back to defaults so a schema change can never make folders fail to load.
extension Folder {
    enum CodingKeys: String, CodingKey {
        case id, name, parentId, credentialId, isExpanded, sortOrder
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Folder()
        self.init()
        id           = try c.decodeIfPresent(UUID.self, forKey: .id) ?? d.id
        name         = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        parentId     = try c.decodeIfPresent(UUID.self, forKey: .parentId)
        credentialId = try c.decodeIfPresent(UUID.self, forKey: .credentialId)
        isExpanded   = try c.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? d.isExpanded
        sortOrder    = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? d.sortOrder
    }
}
