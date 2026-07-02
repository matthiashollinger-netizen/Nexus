import Foundation
import Network

/// A minimal but functional FTP server (RFC 959, passive + active mode) built on
/// Network.framework — no external tools. Lets a network device (or any FTP client)
/// connect to the Mac to download/upload files. Optional username/password auth; the
/// chosen folder is the FTP root.
///
/// Supported: USER/PASS, SYST, FEAT, PWD, CWD, CDUP, TYPE, PASV, PORT, LIST, NLST,
/// RETR, STOR, DELE, MKD, RNFR/RNTO, QUIT.
///
/// Security: PORT (active mode) only dials the client's own control-connection IP
/// (RFC 2577, blocks FTP-bounce/SSRF); password auth is rate-limited per session.
final class NativeFTPServer {

    private let rootDirectory: URL
    private let port: NWEndpoint.Port
    private let username: String
    private let password: String
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.hollinger.Nexus.ftp")
    private var sessions: [ObjectIdentifier: FTPSession] = [:]

    var onLog: ((String) -> Void)?

    /// `username`/`password` empty → anonymous (any login accepted).
    init?(rootDirectory: URL, port: Int, username: String = "", password: String = "") {
        guard port > 0, port <= 65535, let p = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        self.rootDirectory = rootDirectory
        self.port = p
        self.username = username
        self.password = password
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let session = FTPSession(control: connection, rootDirectory: self.rootDirectory,
                                     username: self.username, password: self.password,
                                     queue: self.queue, log: { self.onLog?($0) })
            self.sessions[ObjectIdentifier(connection)] = session
            session.onClose = { [weak self] in
                self?.sessions.removeValue(forKey: ObjectIdentifier(connection))
            }
            session.start()
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onLog?("FTP ready on TCP port \(self?.port.rawValue ?? 0), root \(self?.rootDirectory.path ?? "")")
            case .failed(let e): self?.onLog?("FTP listener failed: \(e.localizedDescription)")
            default: break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        sessions.values.forEach { $0.close() }
        sessions.removeAll()
        listener?.cancel()
        listener = nil
    }
}

// MARK: - Per-client FTP session

private final class FTPSession {
    private let control: NWConnection
    private let rootDirectory: URL
    private let queue: DispatchQueue
    private let log: (String) -> Void

    private let username: String
    private let password: String
    private var providedUser = ""
    private var authenticated = false
    private var failedLogins = 0                // brute-force throttle (RFC-2577-style)

    private var cwd = "/"                       // virtual current dir (relative to root)
    private var dataListener: NWListener?       // passive-mode data listener
    private var pendingDataConnection: NWConnection?
    private var activeEndpoint: NWEndpoint?     // active-mode (PORT) target on the client
    private var renameFrom: String?
    var onClose: (() -> Void)?

    init(control: NWConnection, rootDirectory: URL, username: String, password: String,
         queue: DispatchQueue, log: @escaping (String) -> Void) {
        self.control = control
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.username = username
        self.password = password
        self.queue = queue
        self.log = log
    }

    func start() {
        control.start(queue: queue)
        send("220 Nexus FTP ready")
        receiveCommand()
    }

    func close() {
        dataListener?.cancel()
        pendingDataConnection?.cancel()
        control.cancel()
    }

    // MARK: - Command loop

    private func receiveCommand() {
        control.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, let line = String(data: data, encoding: .utf8) {
                for raw in line.components(separatedBy: "\r\n") where !raw.isEmpty {
                    self.handle(raw)
                }
            }
            if isComplete || error != nil {
                self.close(); self.onClose?()
            } else {
                self.receiveCommand()
            }
        }
    }

    private func handle(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts.first?.uppercased() ?? ""
        let arg = parts.count > 1 ? parts[1] : ""
        log("FTP ← \(cmd) \(cmd == "PASS" ? "****" : arg)")

        // Commands allowed before login; everything else requires authentication.
        let openCommands: Set<String> = ["USER", "PASS", "QUIT", "FEAT", "SYST", "NOOP", "OPTS"]
        if !authenticated && !openCommands.contains(cmd) {
            send("530 Please login with USER and PASS"); return
        }

        switch cmd {
        case "USER":
            providedUser = arg
            if username.isEmpty { authenticated = true; send("230 Login successful") }
            else { send("331 User name okay, need password") }
        case "PASS":
            if username.isEmpty {
                authenticated = true; send("230 Login successful")
            } else if providedUser == username && arg == password {
                authenticated = true; failedLogins = 0; send("230 Login successful")
            } else {
                authenticated = false
                failedLogins += 1
                // Throttle automated guessing: delay the rejection (growing with each
                // failure) and drop the connection after 5 attempts.
                let delay = min(Double(failedLogins), 5.0)
                let shouldDrop = failedLogins >= 5
                queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    self.send("530 Login incorrect")
                    if shouldDrop { self.close(); self.onClose?() }
                }
            }
        case "SYST": send("215 UNIX Type: L8")
        case "FEAT": send("211-Features:\r\n PASV\r\n UTF8\r\n211 End")
        case "OPTS": send("200 OK")
        case "PWD", "XPWD": send("257 \"\(cwd)\" is current directory")
        case "TYPE": send("200 Type set to \(arg)")
        case "NOOP": send("200 OK")
        case "CWD", "XCWD": changeDirectory(arg)
        case "CDUP": changeDirectory("..")
        case "PASV": enterPassive()
        case "PORT": enterActive(arg)
        case "LIST", "NLST": listDirectory(nameOnly: cmd == "NLST")
        case "RETR": retrieve(arg)
        case "STOR": store(arg)
        case "DELE": deleteFile(arg)
        case "MKD", "XMKD": makeDirectory(arg)
        case "RNFR": renameFrom = resolve(arg)?.path; send(renameFrom != nil ? "350 Ready for RNTO" : "550 Not found")
        case "RNTO": performRename(arg)
        case "QUIT": send("221 Goodbye"); close(); onClose?()
        default: send("502 Command not implemented")
        }
    }

    // MARK: - Commands

    private func changeDirectory(_ arg: String) {
        let target = virtualPath(resolvingArg: arg)
        guard let url = resolve(forVirtual: target), isDirectory(url) else {
            send("550 Failed to change directory"); return
        }
        cwd = target
        send("250 Directory changed to \(cwd)")
    }

    private func enterPassive() {
        dataListener?.cancel()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params, on: .any) else {
            send("425 Can't open data connection"); return
        }
        dataListener = listener
        listener.newConnectionHandler = { [weak self] conn in
            self?.pendingDataConnection = conn
            conn.start(queue: self?.queue ?? .global())
        }
        // [weak listener] breaks the listener → stateUpdateHandler → listener cycle
        // that would otherwise leak the NWListener (and its socket) after each PASV.
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            if case .ready = state, let p = listener.port?.rawValue {
                // 227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)
                let ip = EmbeddedServerService.localIPAddress() ?? "127.0.0.1"
                let octets = ip.split(separator: ".").map(String.init)
                guard octets.count == 4 else { self.send("425 Can't open data connection"); return }
                let p1 = Int(p) / 256, p2 = Int(p) % 256
                self.send("227 Entering Passive Mode (\(octets[0]),\(octets[1]),\(octets[2]),\(octets[3]),\(p1),\(p2))")
            }
        }
        listener.start(queue: queue)
    }

    /// Active mode: the client's `PORT h1,h2,h3,h4,p1,p2` tells us where to dial for
    /// data. Many older network devices only do active FTP.
    private func enterActive(_ arg: String) {
        let nums = arg.split(separator: ",").compactMap { Int($0) }
        guard nums.count == 6, nums.allSatisfy({ $0 >= 0 && $0 <= 255 }) else {
            send("501 Syntax error in PORT"); return
        }
        let ip = "\(nums[0]).\(nums[1]).\(nums[2]).\(nums[3])"
        let portNum = nums[4] * 256 + nums[5]
        guard let p = NWEndpoint.Port(rawValue: UInt16(portNum)) else { send("501 Bad port"); return }
        // RFC 2577: the data endpoint MUST be the client itself. Refusing any other
        // address blocks the FTP-bounce / SSRF attack where a client makes the server
        // dial an arbitrary internal host. LAN devices send their own address here.
        guard let clientIP = controlRemoteIP() else {
            send("501 Cannot verify client address"); return
        }
        guard clientIP == ip else {
            log("FTP PORT rejected: \(ip) ≠ client \(clientIP)")
            send("501 PORT address must match the client address"); return
        }
        dataListener?.cancel(); dataListener = nil
        pendingDataConnection = nil
        activeEndpoint = .hostPort(host: NWEndpoint.Host(ip), port: p)
        send("200 PORT command successful")
    }

    private func listDirectory(nameOnly: Bool) {
        guard let dir = resolve(forVirtual: cwd) else { send("550 Failed"); return }
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])) ?? []

        let text: String
        if nameOnly {
            text = entries.map { $0.lastPathComponent }.joined(separator: "\r\n") + "\r\n"
        } else {
            text = entries.map { lsLine(for: $0) }.joined(separator: "\r\n") + "\r\n"
        }
        send("150 Opening data connection")
        sendDataAndClose(Data(text.utf8)) { [weak self] ok in
            self?.send(ok ? "226 Transfer complete" : "426 Connection closed")
        }
    }

    private func retrieve(_ arg: String) {
        guard let url = resolve(arg), let data = try? Data(contentsOf: url) else {
            send("550 File not found"); return
        }
        send("150 Opening data connection (\(data.count) bytes)")
        sendDataAndClose(data) { [weak self] ok in
            self?.log("FTP RETR \(arg): \(ok ? "sent \(data.count) bytes" : "failed")")
            self?.send(ok ? "226 Transfer complete" : "426 Connection closed")
        }
    }

    private func store(_ arg: String) {
        guard let url = resolve(arg) else { send("550 Invalid path"); return }
        send("150 Ready to receive")
        receiveDataToEnd { [weak self] data in
            guard let self else { return }
            do {
                try data.write(to: url, options: .atomic)
                self.log("FTP STOR \(arg): stored \(data.count) bytes")
                self.send("226 Transfer complete")
            } catch {
                self.send("550 Could not store file")
            }
        }
    }

    private func deleteFile(_ arg: String) {
        guard let url = resolve(arg), (try? FileManager.default.removeItem(at: url)) != nil else {
            send("550 Delete failed"); return
        }
        send("250 File deleted")
    }

    private func makeDirectory(_ arg: String) {
        guard let url = resolve(arg),
              (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)) != nil else {
            send("550 Create directory failed"); return
        }
        send("257 Directory created")
    }

    private func performRename(_ arg: String) {
        guard let from = renameFrom, let to = resolve(arg),
              (try? FileManager.default.moveItem(atPath: from, toPath: to.path)) != nil else {
            send("550 Rename failed"); renameFrom = nil; return
        }
        renameFrom = nil
        send("250 Rename successful")
    }

    // MARK: - Data channel helpers

    private func withDataConnection(_ work: @escaping (NWConnection?) -> Void) {
        // Active mode: we dial the client's PORT target.
        if let endpoint = activeEndpoint {
            activeEndpoint = nil
            let conn = NWConnection(to: endpoint, using: .tcp)
            pendingDataConnection = conn
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: conn.stateUpdateHandler = nil; work(conn)
                case .failed, .cancelled:
                    // Release the socket/fd — a bare work(nil) would leak it.
                    conn.stateUpdateHandler = nil; conn.cancel(); work(nil)
                default: break
                }
            }
            conn.start(queue: queue)
            return
        }
        // Passive mode: the client connects to us; poll briefly for the connection.
        func attempt(_ remaining: Int) {
            if let conn = pendingDataConnection {
                work(conn)
            } else if remaining > 0 {
                queue.asyncAfter(deadline: .now() + 0.05) { attempt(remaining - 1) }
            } else {
                work(nil)
            }
        }
        attempt(40)   // up to ~2s
    }

    private func sendDataAndClose(_ data: Data, completion: @escaping (Bool) -> Void) {
        withDataConnection { [weak self] conn in
            guard let conn else { completion(false); return }
            conn.send(content: data, completion: .contentProcessed { _ in
                conn.cancel()
                self?.pendingDataConnection = nil
                self?.dataListener?.cancel(); self?.dataListener = nil
                completion(true)
            })
        }
    }

    private func receiveDataToEnd(completion: @escaping (Data) -> Void) {
        withDataConnection { [weak self] conn in
            guard let conn else { self?.send("425 No data connection"); return }
            var buffer = Data()
            func loop() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
                    if let data { buffer.append(data) }
                    if isComplete {
                        conn.cancel()
                        self?.pendingDataConnection = nil
                        self?.dataListener?.cancel(); self?.dataListener = nil
                        completion(buffer)
                    } else {
                        loop()
                    }
                }
            }
            loop()
        }
    }

    /// The client's source IP on the control connection, used for RFC 2577 active-mode
    /// validation. Returns nil if it can't be determined (active mode is then refused).
    private func controlRemoteIP() -> String? {
        let endpoint = control.currentPath?.remoteEndpoint ?? control.endpoint
        guard case let .hostPort(host, _) = endpoint else { return nil }
        switch host {
        case .ipv4(let addr):
            return addr.rawValue.map(String.init).joined(separator: ".")
        case .ipv6(let addr):
            // Best-effort textual form; drop any scope-id ("fe80::1%en0").
            return "\(addr)".components(separatedBy: "%").first
        case .name(let name, _):
            return name
        @unknown default:
            return nil
        }
    }

    // MARK: - Path resolution (sandboxed to root)

    private func virtualPath(resolvingArg arg: String) -> String {
        if arg == ".." {
            if cwd == "/" { return "/" }
            var comps = cwd.split(separator: "/").map(String.init)
            comps.removeLast()
            return "/" + comps.joined(separator: "/")
        }
        if arg.hasPrefix("/") { return arg }
        return (cwd == "/" ? "/" : cwd + "/") + arg
    }

    /// Resolve a client path argument to a real URL under root (or nil if it escapes).
    private func resolve(_ arg: String) -> URL? {
        let v = arg.hasPrefix("/") ? arg : (cwd == "/" ? "/" : cwd + "/") + arg
        return resolve(forVirtual: v)
    }

    private func resolve(forVirtual virtual: String) -> URL? {
        var rel = virtual
        while rel.hasPrefix("/") { rel.removeFirst() }
        let candidate = rootDirectory.appendingPathComponent(rel).standardizedFileURL
        let rootPath = rootDirectory.path.hasSuffix("/") ? rootDirectory.path : rootDirectory.path + "/"
        if candidate.path == rootDirectory.path || candidate.path.hasPrefix(rootPath) {
            return candidate
        }
        return nil   // path traversal attempt
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func lsLine(for url: URL) -> String {
        let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let isDir = vals?.isDirectory ?? false
        let size = vals?.fileSize ?? 0
        let perms = isDir ? "drwxr-xr-x" : "-rw-r--r--"
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.dateFormat = "MMM dd HH:mm"
        let date = fmt.string(from: vals?.contentModificationDate ?? Date())
        return "\(perms) 1 nexus nexus \(String(format: "%8d", size)) \(date) \(url.lastPathComponent)"
    }

    private func send(_ line: String) {
        log("FTP → \(line)")
        control.send(content: Data((line + "\r\n").utf8), completion: .idempotent)
    }
}
