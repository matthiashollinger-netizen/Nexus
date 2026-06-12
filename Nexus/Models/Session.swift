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
    var isFavorite: Bool = false

    // Reusable quick commands sent to the live terminal (snippets).
    var snippets: [Snippet] = []

    // Default member-wise init (preserved because we add a custom Decodable init below).
    init() {}
}

// MARK: - Tolerant Codable
//
// CRITICAL — DO NOT replace this with the synthesized Codable.
//
// Swift's *synthesized* `init(from:)` IGNORES property default values and requires
// EVERY non-optional key to be present in the JSON, or the whole decode throws
// `keyNotFound`. That caused real data loss (v2.2.0): a `sessions.json` written by an
// older version lacked newly-added non-optional keys (e.g. `connectTimeout`), so
// `JSONDecoder().decode([Session].self)` threw, `loadSessions()` returned `[]`, all
// sessions appeared gone, and the empty array then overwrote the good file.
//
// This hand-written decoder uses `decodeIfPresent(...) ?? default` for EVERY field,
// so missing keys fall back to their defaults and decoding NEVER fails on a schema
// change. Adding a new field here is automatically backward/forward compatible.
// (Encoding stays synthesized — it writes all current fields.)
extension Session {
    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, connectionType, folderId, credentialId
        case description, tags, sortOrder
        case sshPrivateKeyPath, sshUseLegacyAlgorithms, sshStrictHostKeyChecking
        case serialPort, serialBaudRate, serialDataBits, serialStopBits, serialParity, serialFlowControl
        case jumpHost, portForwardings, socks5Proxy
        case rdpUsername, rdpDomain, rdpWidth, rdpHeight, rdpColorDepth
        case rdpFullscreen, rdpClipboardSharing, rdpDriveRedirection, rdpCredentialId
        case connectTimeout, themeId, terminalFontSize, highlightRuleset
        case macroOnConnectId, autoConnectOnLaunch, isFavorite, snippets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Session()   // holds the defaults
        self.init()

        id              = try c.decodeIfPresent(UUID.self, forKey: .id) ?? d.id
        name            = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        host            = try c.decodeIfPresent(String.self, forKey: .host) ?? d.host
        port            = try c.decodeIfPresent(Int.self, forKey: .port) ?? d.port
        username        = try c.decodeIfPresent(String.self, forKey: .username) ?? d.username
        connectionType  = try c.decodeIfPresent(ConnectionType.self, forKey: .connectionType) ?? d.connectionType
        folderId        = try c.decodeIfPresent(UUID.self, forKey: .folderId)
        credentialId    = try c.decodeIfPresent(UUID.self, forKey: .credentialId)
        description     = try c.decodeIfPresent(String.self, forKey: .description) ?? d.description
        tags            = try c.decodeIfPresent([String].self, forKey: .tags) ?? d.tags
        sortOrder       = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? d.sortOrder

        sshPrivateKeyPath        = try c.decodeIfPresent(String.self, forKey: .sshPrivateKeyPath) ?? d.sshPrivateKeyPath
        sshUseLegacyAlgorithms   = try c.decodeIfPresent(Bool.self, forKey: .sshUseLegacyAlgorithms)
        sshStrictHostKeyChecking = try c.decodeIfPresent(Bool.self, forKey: .sshStrictHostKeyChecking) ?? d.sshStrictHostKeyChecking

        serialPort        = try c.decodeIfPresent(String.self, forKey: .serialPort) ?? d.serialPort
        serialBaudRate    = try c.decodeIfPresent(Int.self, forKey: .serialBaudRate) ?? d.serialBaudRate
        serialDataBits    = try c.decodeIfPresent(Int.self, forKey: .serialDataBits) ?? d.serialDataBits
        serialStopBits    = try c.decodeIfPresent(String.self, forKey: .serialStopBits) ?? d.serialStopBits
        serialParity      = try c.decodeIfPresent(String.self, forKey: .serialParity) ?? d.serialParity
        serialFlowControl = try c.decodeIfPresent(String.self, forKey: .serialFlowControl) ?? d.serialFlowControl

        jumpHost        = try c.decodeIfPresent(JumpHost.self, forKey: .jumpHost)
        portForwardings = try c.decodeIfPresent([PortForwarding].self, forKey: .portForwardings) ?? d.portForwardings
        socks5Proxy     = try c.decodeIfPresent(SOCKS5Config.self, forKey: .socks5Proxy)

        rdpUsername         = try c.decodeIfPresent(String.self, forKey: .rdpUsername) ?? d.rdpUsername
        rdpDomain           = try c.decodeIfPresent(String.self, forKey: .rdpDomain) ?? d.rdpDomain
        rdpWidth            = try c.decodeIfPresent(Int.self, forKey: .rdpWidth) ?? d.rdpWidth
        rdpHeight           = try c.decodeIfPresent(Int.self, forKey: .rdpHeight) ?? d.rdpHeight
        rdpColorDepth       = try c.decodeIfPresent(Int.self, forKey: .rdpColorDepth) ?? d.rdpColorDepth
        rdpFullscreen       = try c.decodeIfPresent(Bool.self, forKey: .rdpFullscreen) ?? d.rdpFullscreen
        rdpClipboardSharing = try c.decodeIfPresent(Bool.self, forKey: .rdpClipboardSharing) ?? d.rdpClipboardSharing
        rdpDriveRedirection = try c.decodeIfPresent(Bool.self, forKey: .rdpDriveRedirection) ?? d.rdpDriveRedirection
        rdpCredentialId     = try c.decodeIfPresent(UUID.self, forKey: .rdpCredentialId)

        connectTimeout      = try c.decodeIfPresent(Int.self, forKey: .connectTimeout) ?? d.connectTimeout
        themeId             = try c.decodeIfPresent(UUID.self, forKey: .themeId)
        terminalFontSize    = try c.decodeIfPresent(Double.self, forKey: .terminalFontSize)
        highlightRuleset    = try c.decodeIfPresent(String.self, forKey: .highlightRuleset)
        macroOnConnectId    = try c.decodeIfPresent(UUID.self, forKey: .macroOnConnectId)
        autoConnectOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .autoConnectOnLaunch) ?? d.autoConnectOnLaunch
        isFavorite          = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? d.isFavorite
        snippets            = try c.decodeIfPresent([Snippet].self, forKey: .snippets) ?? d.snippets
    }
}

// MARK: - Snippet
//
// A reusable command a user can fire into the live terminal for this session
// (e.g. "show running-config", "show version"). Sent verbatim followed by a
// newline. Optional `sendReturn = false` lets a snippet just prefill text.
struct Snippet: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var command: String = ""
    var sendReturn: Bool = true

    init() {}
    init(title: String, command: String, sendReturn: Bool = true) {
        self.title = title; self.command = command; self.sendReturn = sendReturn
    }
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
