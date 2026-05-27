import Foundation

enum ConnectionType: String, Codable, CaseIterable, Identifiable {
    case ssh = "SSH"
    case telnet = "Telnet"
    case serial = "Serial"

    var id: String { rawValue }

    var defaultPort: Int {
        switch self {
        case .ssh: return 22
        case .telnet: return 23
        case .serial: return 0
        }
    }

    var systemImage: String {
        switch self {
        case .ssh: return "terminal"
        case .telnet: return "network"
        case .serial: return "cable.connector"
        }
    }
}

struct Session: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var connectionType: ConnectionType = .ssh
    var folderId: UUID? = nil
    var credentialId: UUID? = nil
    var description: String = ""
    var tags: [String] = []
    var sortOrder: Int = 0

    // SSH
    var sshPrivateKeyPath: String = ""
    var sshUseLegacyAlgorithms: Bool? = nil
    var sshStrictHostKeyChecking: Bool = false

    // Serial
    var serialPort: String = ""
    var serialBaudRate: Int = 9600
    var serialDataBits: Int = 8
    var serialStopBits: String = "1"
    var serialParity: String = "none"
    var serialFlowControl: String = "none"
}
