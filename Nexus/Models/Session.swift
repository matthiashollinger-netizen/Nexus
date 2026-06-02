import Foundation

enum ConnectionType: String, Codable, CaseIterable, Identifiable {
    case ssh    = "SSH"
    case telnet = "Telnet"
    case serial = "Serial"
    case rdp    = "RDP"

    var id: String { rawValue }

    var defaultPort: Int {
        switch self {
        case .ssh:    return 22
        case .telnet: return 23
        case .serial: return 0
        case .rdp:    return 3389
        }
    }

    var systemImage: String {
        switch self {
        case .ssh:    return "terminal"
        case .telnet: return "network"
        case .serial: return "cable.connector"
        case .rdp:    return "desktopcomputer"
        }
    }

    /// Whether this protocol is fully supported without external tools.
    /// RDP is deactivated: no embeddable native RDP library exists, and FreeRDP
    /// requires XQuartz/Homebrew — which contradicts the self-contained goal.
    /// See WEEK_REPORT.md (Aufgabe 4) for the evaluation and the path forward.
    var isAvailable: Bool {
        switch self {
        case .ssh, .telnet, .serial: return true
        case .rdp:                   return false
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

    // SSH Gateway / Tunneling
    var jumpHost: JumpHost? = nil
    var portForwardings: [PortForwarding] = []
    var socks5Proxy: SOCKS5Config? = nil

    // RDP
    var rdpUsername: String = ""
    var rdpDomain: String = ""
    var rdpWidth: Int = 1920
    var rdpHeight: Int = 1080
    var rdpColorDepth: Int = 32
    var rdpFullscreen: Bool = false
    var rdpClipboardSharing: Bool = true
    var rdpDriveRedirection: Bool = false
    var rdpCredentialId: UUID? = nil

    // Connection behaviour
    var connectTimeout: Int = 10

    // Terminal & appearance (per-session overrides; nil = use global default)
    var themeId: UUID? = nil
    var terminalFontSize: Double? = nil
    var highlightRuleset: String? = nil   // nil = global; "" or a HighlightRuleset rawValue

    // Behaviour
    var macroOnConnectId: UUID? = nil
    var autoConnectOnLaunch: Bool = false
}

// MARK: - SSH Gateway Models

struct JumpHost: Codable, Equatable, Hashable {
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var credentialId: UUID? = nil
    var usePrivateKey: Bool = false
    var privateKeyPath: String = ""
}

struct PortForwarding: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var type: ForwardingType = .local
    var localPort: Int = 0
    var remoteHost: String = ""
    var remotePort: Int = 0
    var description: String = ""

    enum ForwardingType: String, Codable, CaseIterable, Identifiable {
        case local   = "local"
        case remote  = "remote"
        case dynamic = "dynamic"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .local:   return "Local (-L)"
            case .remote:  return "Remote (-R)"
            case .dynamic: return "Dynamic / SOCKS5 (-D)"
            }
        }
    }
}

struct SOCKS5Config: Codable, Equatable, Hashable {
    var enabled: Bool = false
    var localPort: Int = 1080
}

// MARK: - RDP + ConnectionType extension

extension ConnectionType {
    static var allCasesIncludingRDP: [ConnectionType] { allCases + [.rdp] }
}
