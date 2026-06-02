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

    enum ServerType: String, Codable, CaseIterable {
        case http = "HTTP"
        case ftp  = "FTP"
        case tftp = "TFTP"

        var displayName: String { rawValue }
        var systemImage: String {
            switch self {
            case .http: return "globe"
            case .ftp:  return "server.rack"
            case .tftp: return "arrow.up.arrow.down.circle"
            }
        }
        var defaultPort: Int {
            switch self {
            case .http: return 8080
            case .ftp:  return 2121
            case .tftp: return 69
            }
        }
    }
}

// MARK: - Embedded Server Service

@Observable
final class EmbeddedServerService {
    static let shared = EmbeddedServerService()

    var servers: [EmbeddedServer] = []

    private var processes: [UUID: Process] = [:]
    private var serverLogs: [UUID: [String]] = [:]

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

        // Check if port is available
        if isPortInUse(server.port) {
            throw EmbeddedServerError.portInUse(server.port)
        }

        let process = try buildProcess(for: server)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Capture logs
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                DispatchQueue.main.async {
                    var existing = self.serverLogs[server.id] ?? []
                    existing.append(contentsOf: line.components(separatedBy: .newlines).filter { !$0.isEmpty })
                    if existing.count > 200 { existing = Array(existing.suffix(200)) }
                    self.serverLogs[server.id] = existing
                }
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.processes.removeValue(forKey: server.id)
                if let i = self.servers.firstIndex(where: { $0.id == server.id }) {
                    self.servers[i].isRunning = false
                }
            }
        }

        try process.run()
        processes[server.id] = process
        servers[idx].isRunning = true
    }

    // MARK: - Stop

    func stop(_ server: EmbeddedServer) {
        guard let proc = processes[server.id] else { return }
        proc.terminate()
        processes.removeValue(forKey: server.id)
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx].isRunning = false
        }
    }

    // MARK: - Logs

    func logs(for server: EmbeddedServer) -> [String] {
        serverLogs[server.id] ?? []
    }

    // MARK: - Helpers

    private func buildProcess(for server: EmbeddedServer) throws -> Process {
        let process = Process()
        let rootDir = server.rootDirectory.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : server.rootDirectory

        switch server.type {
        case .http:
            guard let python = findPython3() else { throw EmbeddedServerError.binaryNotFound("python3") }
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = ["-m", "http.server", "\(server.port)", "--directory", rootDir]

        case .ftp:
            guard let python = findPython3() else { throw EmbeddedServerError.binaryNotFound("python3") }
            // pyftpdlib may not be installed — use a fallback
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = ["-m", "pyftpdlib", "-p", "\(server.port)", "-d", rootDir]

        case .tftp:
            let tftp = "/usr/libexec/tftpd"
            guard FileManager.default.fileExists(atPath: tftp) else {
                throw EmbeddedServerError.binaryNotFound("tftpd")
            }
            process.executableURL = URL(fileURLWithPath: tftp)
            process.arguments = ["-i", rootDir, "\(server.port)"]
        }

        return process
    }

    private func findPython3() -> String? {
        let candidates = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func isPortInUse(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
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

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let bin): return "Required binary '\(bin)' not found"
        case .portInUse(let port): return "Port \(port) is already in use"
        }
    }
}
