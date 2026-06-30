import Foundation
import Network

// MARK: - Embedded Server Model

struct EmbeddedServer: Identifiable, Codable {
    var id: UUID = UUID()
    var type: ServerType
    var rootDirectory: String = ""
    var port: Int
    var isRunning: Bool = false
    var autoStart: Bool = false
    // FTP login (empty = anonymous). Only used by the FTP server.
    var ftpUsername: String = ""
    var ftpPassword: String = ""

    enum ServerType: String, Codable, CaseIterable, Identifiable {
        case http   = "HTTP"
        case tftp   = "TFTP"
        case ftp    = "FTP"
        case syslog = "Syslog"
        case sftp   = "SFTP"
        case telnet = "Telnet"

        var id: String { rawValue }
        var displayName: String { rawValue }
        var systemImage: String {
            switch self {
            case .http:   return "globe"
            case .tftp:   return "arrow.up.arrow.down.circle"
            case .ftp:    return "server.rack"
            case .syslog: return "doc.text.magnifyingglass"
            case .sftp:   return "folder.badge.gearshape"
            case .telnet: return "terminal"
            }
        }
        var defaultPort: Int {
            switch self {
            case .http:   return 8080
            case .tftp:   return 6969   // 69 needs root → default to a high port
            case .ftp:    return 2121
            case .syslog: return 5514   // 514 needs root → default to a high port
            case .sftp:   return 22
            case .telnet: return 23
            }
        }

        /// Can this server be started from within Nexus, self-contained (no external tool)?
        /// - HTTP: native NativeHTTPServer ✅
        /// - TFTP: native NativeTFTPServer ✅ (the Cisco/HP standard; high port avoids root)
        /// - FTP:  native NativeFTPServer ✅ (passive mode)
        /// - Syslog: native NativeSyslogServer ✅ (receive switch logs; high port avoids root)
        /// - SFTP: requires a full SSH server → not shippable without system sshd → off
        /// - Telnet: not needed (user) and would expose a shell → off
        var isAvailable: Bool {
            switch self {
            case .http, .tftp, .ftp, .syslog: return true
            case .sftp, .telnet:              return false
            }
        }

        /// Syslog has no served root directory (it receives, not serves).
        var usesRootDirectory: Bool {
            switch self {
            case .syslog: return false
            default:      return true
            }
        }

        /// Localized one-line note explaining the status of a non-startable type.
        var noteKey: String {
            switch self {
            case .sftp:   return "server.note.sftp"
            case .telnet: return "server.note.telnet"
            default:      return ""
            }
        }
    }
}

// Tolerant decoder — see Session.swift for the rationale. Lets a new field (e.g.
// ftpUsername/ftpPassword) be added without resetting the user's saved servers.
extension EmbeddedServer {
    enum CodingKeys: String, CodingKey {
        case id, type, rootDirectory, port, isRunning, autoStart, ftpUsername, ftpPassword
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type          = try c.decodeIfPresent(ServerType.self, forKey: .type) ?? .http
        rootDirectory = try c.decodeIfPresent(String.self, forKey: .rootDirectory) ?? ""
        port          = try c.decodeIfPresent(Int.self, forKey: .port) ?? type.defaultPort
        isRunning     = false   // never restore as running
        autoStart     = try c.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        ftpUsername   = try c.decodeIfPresent(String.self, forKey: .ftpUsername) ?? ""
        ftpPassword   = try c.decodeIfPresent(String.self, forKey: .ftpPassword) ?? ""
    }
}

// MARK: - Embedded Server Service

@Observable
final class EmbeddedServerService {
    static let shared = EmbeddedServerService()

    var servers: [EmbeddedServer] = []

    private var httpServers: [UUID: NativeHTTPServer] = [:]
    private var tftpServers: [UUID: NativeTFTPServer] = [:]
    private var ftpServers: [UUID: NativeFTPServer] = [:]
    private var syslogServers: [UUID: NativeSyslogServer] = [:]
    private var serverLogs: [UUID: [String]] = [:]

    /// The live syslog collector for a server (for the structured log view).
    func syslogServer(for server: EmbeddedServer) -> NativeSyslogServer? {
        syslogServers[server.id]
    }

    private var appSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent("Nexus")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var serversFileURL: URL {
        appSupportURL.appendingPathComponent("servers.json")
    }

    // MARK: - Persistence

    func loadServers() {
        guard let data = try? Data(contentsOf: serversFileURL),
              let decoded = try? JSONDecoder().decode([EmbeddedServer].self, from: data) else { return }
        servers = decoded.map { var s = $0; s.isRunning = false; return s }
    }

    func saveServers() {
        var toSave = servers
        for i in toSave.indices { toSave[i].isRunning = false }
        guard let data = try? JSONEncoder().encode(toSave) else { return }
        try? data.write(to: serversFileURL, options: .atomicWrite)
    }

    // MARK: - Start

    func start(_ server: EmbeddedServer) async throws {
        guard let idx = servers.firstIndex(where: { $0.id == server.id }) else { return }

        guard server.type.isAvailable else {
            throw EmbeddedServerError.notAvailable(server.type.displayName)
        }

        let rootURL = URL(fileURLWithPath: server.rootDirectory.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : server.rootDirectory)

        // Logging closure shared by all native servers.
        let log: (String) -> Void = { [weak self] line in
            DispatchQueue.main.async {
                guard let self else { return }
                var existing = self.serverLogs[server.id] ?? []
                existing.append(line)
                if existing.count > 200 { existing = Array(existing.suffix(200)) }
                self.serverLogs[server.id] = existing
            }
        }

        switch server.type {
        case .http:
            if isPortInUse(server.port) { throw EmbeddedServerError.portInUse(server.port) }
            guard let s = NativeHTTPServer(rootDirectory: rootURL, port: server.port) else {
                throw EmbeddedServerError.portInUse(server.port)
            }
            s.onLog = log
            try s.start()
            httpServers[server.id] = s

        case .tftp:
            // TFTP is UDP — the TCP isPortInUse check doesn't apply; NWListener reports conflicts.
            guard let s = NativeTFTPServer(rootDirectory: rootURL, port: server.port) else {
                throw EmbeddedServerError.portInUse(server.port)
            }
            s.onLog = log
            try s.start()
            tftpServers[server.id] = s

        case .ftp:
            if isPortInUse(server.port) { throw EmbeddedServerError.portInUse(server.port) }
            guard let s = NativeFTPServer(rootDirectory: rootURL, port: server.port,
                                          username: server.ftpUsername, password: server.ftpPassword) else {
                throw EmbeddedServerError.portInUse(server.port)
            }
            s.onLog = log
            try s.start()
            ftpServers[server.id] = s

        case .syslog:
            guard let s = NativeSyslogServer(port: server.port) else {
                throw EmbeddedServerError.portInUse(server.port)
            }
            s.onLog = log
            try s.start()
            syslogServers[server.id] = s

        case .sftp, .telnet:
            throw EmbeddedServerError.notAvailable(server.type.displayName)
        }

        servers[idx].isRunning = true
    }

    // MARK: - Stop

    func stop(_ server: EmbeddedServer) {
        httpServers[server.id]?.stop(); httpServers.removeValue(forKey: server.id)
        tftpServers[server.id]?.stop(); tftpServers.removeValue(forKey: server.id)
        ftpServers[server.id]?.stop(); ftpServers.removeValue(forKey: server.id)
        syslogServers[server.id]?.stop(); syslogServers.removeValue(forKey: server.id)
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx].isRunning = false
        }
    }

    // MARK: - Logs

    func logs(for server: EmbeddedServer) -> [String] {
        serverLogs[server.id] ?? []
    }

    // MARK: - Reachable address

    /// Returns the Mac's primary LAN IPv4 address (for "tftp://<ip>:<port>" hints).
    static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            // Up, running, not loopback, IPv4
            guard (flags & (IFF_UP|IFF_RUNNING)) == (IFF_UP|IFF_RUNNING),
                  (flags & IFF_LOOPBACK) == 0,
                  addr.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            // Prefer en0/en1 (Wi-Fi/Ethernet) over virtual interfaces.
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &host,
                           socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                address = String(cString: host)
                break
            }
        }
        return address
    }

    // MARK: - Helpers

    private func isPortInUse(_ port: Int) -> Bool {
        // Guard the range first — UInt16(port) traps on overflow.
        guard let port16 = UInt16(exactly: port) else { return false }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port16.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sptr in
                connect(fd, sptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    // MARK: - Auto start

    func startAutoStartServers() {
        for server in servers where server.autoStart {
            Task {
                try? await start(server)
            }
        }
    }
}

// MARK: - Errors

enum EmbeddedServerError: LocalizedError {
    case binaryNotFound(String)
    case portInUse(Int)
    case notAvailable(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let bin):
            return String(format: String(localized: "server.error.binary_not_found"), bin)
        case .portInUse(let port):
            return String(format: String(localized: "server.error.port_in_use"), port)
        case .notAvailable(let name):
            return String(format: String(localized: "server.error.not_available"), name)
        }
    }
}
