import Foundation

// MARK: - SFTP Item Model

struct SFTPItem: Identifiable {
    let id: UUID
    var name: String
    var path: String
    var isDirectory: Bool
    var isSymlink: Bool
    var size: Int64
    var permissions: String  // "rwxr-xr-x"
    var modifiedDate: Date
    var owner: String
    var group: String
}

// MARK: - SFTP Errors

enum SFTPError: LocalizedError {
    case sftpNotFound
    case authenticationFailed
    case connectionFailed(String)
    case operationFailed(String)
    case parseError
    case directoryNotEmpty

    var errorDescription: String? {
        switch self {
        case .sftpNotFound:            return "sftp binary not found at /usr/bin/sftp"
        case .authenticationFailed:    return "Authentication failed — check credentials"
        case .connectionFailed(let m): return "Connection failed: \(m)"
        case .operationFailed(let m):  return "Operation failed: \(m)"
        case .parseError:              return "Could not parse SFTP output"
        case .directoryNotEmpty:       return "Directory is not empty — delete contents first"
        }
    }
}

// MARK: - SFTP connection parameters
//
// Bundles everything an SFTP batch needs. The `options` carry the SAME legacy
// algorithms / host-key / timeout / jump-host settings the SSH terminal uses, so
// SFTP can reach exactly the servers the terminal can (the old SFTP code omitted
// the legacy-algorithm flags → "Authentication failed" / reset on old switches).
struct SFTPConnection {
    var host: String
    var port: Int
    var username: String
    var password: String?
    var keyPath: String?
    var options: SSHConnectionOptions
}

// MARK: - SFTP Service

actor SFTPService {
    static let shared = SFTPService()

    private let sftp = "/usr/bin/sftp"

    // MARK: - Argument building (pure, testable)

    /// Builds the `/usr/bin/sftp` argument list for `conn`. Note the port flag is
    /// `-P` (UPPERCASE) — sftp differs from ssh which uses `-p`.
    ///
    /// CRITICAL — do NOT add sftp's `-b` batch flag. `-b` implies ssh `BatchMode=yes`,
    /// which DISABLES SSH_ASKPASS password authentication (ssh then only attempts key
    /// auth, fails, and returns "Permission denied (publickey,password)" without ever
    /// prompting). That made the SFTP browser fail "Authentication failed" on every
    /// password-auth host even though the identical password worked in the SSH
    /// terminal (the terminal masks it by *typing* the password as a fallback; SFTP
    /// has none). Instead we feed the command list through the process's stdin pipe,
    /// which sftp reads non-interactively while still allowing askpass password auth.
    /// Verified against a real host (publickey → password → askpass invoked).
    nonisolated func buildArguments(_ conn: SFTPConnection) -> [String] {
        // Split "user@host" if present.
        var effectiveUser = conn.username
        var effectiveHost = conn.host
        if conn.host.contains("@"), let atRange = conn.host.range(of: "@", options: .backwards) {
            let parsedUser = String(conn.host[..<atRange.lowerBound])
            let parsedHost = String(conn.host[atRange.upperBound...])
            if effectiveUser.isEmpty { effectiveUser = parsedUser }
            effectiveHost = parsedHost
        }

        var args: [String] = []
        args += conn.options.commonOptionFlags()   // ConnectTimeout, legacy algos, StrictHostKey
        args += ["-P", "\(conn.port)"]              // UPPERCASE -P for sftp
        args += conn.options.jumpHostFlag()         // -J jump host (same as ssh)

        if let kp = conn.keyPath, !kp.isEmpty {
            args += ["-i", kp]
        }
        if effectiveUser.isEmpty {
            args += [effectiveHost]
        } else {
            args += ["\(effectiveUser)@\(effectiveHost)"]
        }
        return args
    }

    // MARK: - Public API

    func listDirectory(_ conn: SFTPConnection, path: String) async throws -> [SFTPItem] {
        let output = try await runBatch(conn, commands: "ls -la \"\(path)\"\nquit\n")
        return parseLsOutput(output, basePath: path)
    }

    /// Resolves the login (home) directory via `pwd` and lists it in one batch.
    /// Used on first connect so the browser lands where the user actually starts —
    /// listing "/" often appears empty or is restricted on many servers/devices.
    func listHome(_ conn: SFTPConnection) async throws -> (path: String, items: [SFTPItem]) {
        let output = try await runBatch(conn, commands: "pwd\nls -la\nquit\n")
        let home = parseRemoteWorkingDirectory(output) ?? "/"
        let items = parseLsOutput(output, basePath: home)
        return (home, items)
    }

    /// Extracts the path from sftp's `pwd` output line:
    /// "Remote working directory: /home/user"
    func parseRemoteWorkingDirectory(_ output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            if let r = line.range(of: "Remote working directory:") {
                let path = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !path.isEmpty { return path }
            }
        }
        return nil
    }

    func downloadFile(_ conn: SFTPConnection, remotePath: String, to localURL: URL) async throws {
        let output = try await runBatch(conn, commands: "get \"\(remotePath)\" \"\(localURL.path)\"\nquit\n")
        let low = output.lowercased()
        if low.contains("no such file") || low.contains("permission denied") || low.contains("failure") {
            throw SFTPError.operationFailed(output)
        }
    }

    func uploadFile(_ conn: SFTPConnection, from localURL: URL, remotePath: String) async throws {
        let output = try await runBatch(conn, commands: "put \"\(localURL.path)\" \"\(remotePath)\"\nquit\n")
        let low = output.lowercased()
        if low.contains("permission denied") || low.contains("failure") {
            throw SFTPError.operationFailed(output)
        }
    }

    func rename(_ conn: SFTPConnection, from: String, to: String) async throws {
        let output = try await runBatch(conn, commands: "rename \"\(from)\" \"\(to)\"\nquit\n")
        let low = output.lowercased()
        if low.contains("failure") || low.contains("permission denied") || low.contains("no such file") {
            throw SFTPError.operationFailed(output)
        }
    }

    func delete(_ conn: SFTPConnection, path: String, isDirectory: Bool) async throws {
        // rmdir only works on empty directories — SFTP protocol limitation.
        let cmd = isDirectory ? "rmdir \"\(path)\"" : "rm \"\(path)\""
        let output = try await runBatch(conn, commands: "\(cmd)\nquit\n")
        let low = output.lowercased()
        if isDirectory && (low.contains("failure") || low.contains("not empty")) {
            throw SFTPError.directoryNotEmpty
        }
        if low.contains("permission denied") || low.contains("no such file") {
            throw SFTPError.operationFailed(output)
        }
    }

    func createDirectory(_ conn: SFTPConnection, path: String) async throws {
        let output = try await runBatch(conn, commands: "mkdir \"\(path)\"\nquit\n")
        let low = output.lowercased()
        if low.contains("failure") || low.contains("permission denied") {
            throw SFTPError.operationFailed(output)
        }
    }

    // MARK: - Private: Run batch SFTP

    private func runBatch(_ conn: SFTPConnection, commands: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: sftp) else {
            throw SFTPError.sftpNotFound
        }

        let args = buildArguments(conn)
        let password = conn.password

        // Temp askpass script path — declared here so we can clean up in terminationHandler
        var askpassScriptPath: String? = nil

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: sftp)
            process.arguments = args

            // Build environment
            var env = ProcessInfo.processInfo.environment
            // Clear any inherited SSH_ASKPASS that might interfere
            env.removeValue(forKey: "SSH_ASKPASS")
            env.removeValue(forKey: "SSH_ASKPASS_REQUIRE")
            env.removeValue(forKey: "DISPLAY")

            if let pwd = password, !pwd.isEmpty {
                // Write temp askpass script. SSH_ASKPASS_REQUIRE=force ensures SSH
                // always calls the helper instead of trying interactive input.
                // DISPLAY=: is required on macOS — empty string or ":0" both work
                // but bare ":" is most reliable across SSH versions.
                let scriptPath = createAskPassScript(password: pwd)
                askpassScriptPath = scriptPath
                env["SSH_ASKPASS"]         = scriptPath
                env["SSH_ASKPASS_REQUIRE"] = "force"
                env["DISPLAY"]             = ":"
            }
            process.environment = env

            let stdin  = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput  = stdin
            process.standardOutput = stdout
            process.standardError  = stderr

            do {
                try process.run()
            } catch {
                // Clean up askpass script if process never launched
                if let p = askpassScriptPath { try? FileManager.default.removeItem(atPath: p) }
                continuation.resume(throwing: SFTPError.connectionFailed(error.localizedDescription))
                return
            }

            // Write commands to stdin, then close to signal EOF
            if let data = commands.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
                try? stdin.fileHandleForWriting.close()
            }

            process.terminationHandler = { _ in
                // Clean up temp askpass script — always, regardless of success/failure
                if let p = askpassScriptPath {
                    try? FileManager.default.removeItem(atPath: p)
                }

                let outData  = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData  = stderr.fileHandleForReading.readDataToEndOfFile()
                let output   = String(data: outData, encoding: .utf8) ?? ""
                let errStr   = String(data: errData, encoding: .utf8) ?? ""
                let combined = output + errStr
                let low      = errStr.lowercased()

                if low.contains("permission denied") || low.contains("authentication failed") ||
                   low.contains("publickey") && low.contains("failed") {
                    continuation.resume(throwing: SFTPError.authenticationFailed)
                } else if low.contains("connection refused") || low.contains("no route to host") ||
                          low.contains("could not resolve") || low.contains("timed out") {
                    continuation.resume(throwing: SFTPError.connectionFailed(errStr))
                } else {
                    continuation.resume(returning: combined)
                }
            }
        }
    }

    // MARK: - Askpass script helper

    /// Creates a temporary shell script that outputs `password` to stdout.
    /// The caller is responsible for deleting the file after use.
    private func createAskPassScript(password: String) -> String {
        // Escape characters that are special inside double-quoted shell strings
        let escaped = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$",  with: "\\$")
            .replacingOccurrences(of: "`",  with: "\\`")
        let script = "#!/bin/sh\necho \"\(escaped)\"\n"
        let path = NSTemporaryDirectory() + "nexus_sftp_\(UUID().uuidString).sh"
        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        return path
    }

    // MARK: - Parse `ls -la` output

    func parseLsOutput(_ output: String, basePath: String) -> [SFTPItem] {
        var items: [SFTPItem] = []
        // Normalize base path: always end with exactly one "/"
        let normalizedBase: String = {
            var b = basePath
            while b.hasSuffix("//") { b = String(b.dropLast()) }
            return b.hasSuffix("/") ? b : b + "/"
        }()

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard !trimmed.hasPrefix("total "),
                  !trimmed.hasPrefix("sftp>"),
                  !trimmed.hasPrefix("Connected to"),
                  !trimmed.hasPrefix("sftp: "),
                  !trimmed.hasPrefix("Changing to:") else { continue }

            if let item = parseLsLine(trimmed, basePath: normalizedBase) {
                if item.name == "." || item.name == ".." { continue }
                items.append(item)
            }
        }
        return items
    }

    // Parse a single `ls -la` line:
    // drwxr-xr-x  2 user group  4096 May 29 10:00 dirname
    // lrwxrwxrwx  1 user group    12 May 29 10:00 link -> target
    func parseLsLine(_ line: String, basePath: String) -> SFTPItem? {
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 9 else { return nil }

        let permStr = parts[0]
        // Skip lines that don't look like permission strings
        guard permStr.count >= 10,
              permStr.first.map({ "-dlcbps".contains($0) }) == true else { return nil }

        let owner   = parts[2]
        let group   = parts[3]
        let sizeStr = parts[4]
        let nameParts = Array(parts.dropFirst(8))
        var name = nameParts.joined(separator: " ")

        var isSymlink = false
        if permStr.hasPrefix("l") {
            isSymlink = true
            if let arrowRange = name.range(of: " -> ") {
                name = String(name[..<arrowRange.lowerBound])
            }
        }

        // sftp's `ls -la <path>` lists entries PREFIXED with the directory
        // ("/home/pi/node/bin"), unlike `ls -la` of the CWD which yields basenames.
        // Keep only the basename so rows read cleanly and item.path stays correct.
        // (Filenames can't contain "/", so this is always safe.)
        if name.contains("/") {
            name = (name as NSString).lastPathComponent
        }

        let isDirectory = permStr.hasPrefix("d")
        let size        = Int64(sizeStr) ?? 0
        let permissions = String(permStr.dropFirst())

        let dateStr     = "\(parts[5]) \(parts[6]) \(parts[7])"
        let modifiedDate = parseDate(dateStr) ?? Date()

        // Normalised path: basePath already ends with "/", name has no leading "/"
        let itemPath = basePath + name

        return SFTPItem(
            id: UUID(),
            name: name,
            path: itemPath,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            size: size,
            permissions: permissions,
            modifiedDate: modifiedDate,
            owner: owner,
            group: group
        )
    }

    private func parseDate(_ str: String) -> Date? {
        let withTime = DateFormatter()
        withTime.locale = Locale(identifier: "en_US_POSIX")
        withTime.dateFormat = "MMM d HH:mm"

        let withYear = DateFormatter()
        withYear.locale = Locale(identifier: "en_US_POSIX")
        withYear.dateFormat = "MMM d yyyy"

        return withTime.date(from: str) ?? withYear.date(from: str)
    }
}
