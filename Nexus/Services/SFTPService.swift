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

    var errorDescription: String? {
        switch self {
        case .sftpNotFound:         return "sftp binary not found at /usr/bin/sftp"
        case .authenticationFailed: return "Authentication failed"
        case .connectionFailed(let m): return "Connection failed: \(m)"
        case .operationFailed(let m):  return "Operation failed: \(m)"
        case .parseError:           return "Could not parse SFTP output"
        }
    }
}

// MARK: - SFTP Service

actor SFTPService {
    static let shared = SFTPService()

    private let sftp = "/usr/bin/sftp"

    // MARK: - Public API

    func listDirectory(host: String, port: Int, username: String, password: String?,
                       keyPath: String?, path: String) async throws -> [SFTPItem] {
        let commands = "ls -la \"\(path)\"\nquit\n"
        let output = try await runBatch(host: host, port: port, username: username,
                                        password: password, keyPath: keyPath,
                                        commands: commands)
        return parseLsOutput(output, basePath: path)
    }

    func downloadFile(host: String, port: Int, username: String, password: String?,
                      keyPath: String?, remotePath: String, to localURL: URL) async throws {
        let commands = "get \"\(remotePath)\" \"\(localURL.path)\"\nquit\n"
        let output = try await runBatch(host: host, port: port, username: username,
                                        password: password, keyPath: keyPath,
                                        commands: commands)
        if output.lowercased().contains("no such file") || output.lowercased().contains("permission denied") {
            throw SFTPError.operationFailed(output)
        }
    }

    func uploadFile(host: String, port: Int, username: String, password: String?,
                    keyPath: String?, from localURL: URL, remotePath: String) async throws {
        let commands = "put \"\(localURL.path)\" \"\(remotePath)\"\nquit\n"
        let output = try await runBatch(host: host, port: port, username: username,
                                        password: password, keyPath: keyPath,
                                        commands: commands)
        if output.lowercased().contains("permission denied") || output.lowercased().contains("failure") {
            throw SFTPError.operationFailed(output)
        }
    }

    func rename(host: String, port: Int, username: String, password: String?,
                keyPath: String?, from: String, to: String) async throws {
        let commands = "rename \"\(from)\" \"\(to)\"\nquit\n"
        let output = try await runBatch(host: host, port: port, username: username,
                                        password: password, keyPath: keyPath,
                                        commands: commands)
        if output.lowercased().contains("failure") || output.lowercased().contains("permission denied") {
            throw SFTPError.operationFailed(output)
        }
    }

    func delete(host: String, port: Int, username: String, password: String?,
                keyPath: String?, path: String, isDirectory: Bool) async throws {
        let cmd = isDirectory ? "rmdir \"\(path)\"" : "rm \"\(path)\""
        let commands = "\(cmd)\nquit\n"
        let output = try await runBatch(host: host, port: port, username: username,
                                        password: password, keyPath: keyPath,
                                        commands: commands)
        if output.lowercased().contains("failure") || output.lowercased().contains("permission denied") {
            throw SFTPError.operationFailed(output)
        }
    }

    func createDirectory(host: String, port: Int, username: String, password: String?,
                         keyPath: String?, path: String) async throws {
        let commands = "mkdir \"\(path)\"\nquit\n"
        let output = try await runBatch(host: host, port: port, username: username,
                                        password: password, keyPath: keyPath,
                                        commands: commands)
        if output.lowercased().contains("failure") || output.lowercased().contains("permission denied") {
            throw SFTPError.operationFailed(output)
        }
    }

    // MARK: - Private: Run batch SFTP

    private func runBatch(host: String, port: Int, username: String,
                          password: String?, keyPath: String?,
                          commands: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: sftp) else {
            throw SFTPError.sftpNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: sftp)

            var args = ["-b", "-",
                        "-o", "ConnectTimeout=10",
                        "-o", "StrictHostKeyChecking=no",
                        "-o", "UserKnownHostsFile=/dev/null",
                        "-P", "\(port)"]

            if let kp = keyPath, !kp.isEmpty {
                args += ["-i", kp]
            }

            if let user = username.isEmpty ? nil : username {
                args += ["\(user)@\(host)"]
            } else {
                args += [host]
            }

            process.arguments = args

            // Environment: suppress SSH_ASKPASS interference
            var env = ProcessInfo.processInfo.environment
            env["SSH_ASKPASS"] = nil
            env["DISPLAY"] = nil
            // BatchMode disables password prompts cleanly
            // We inject password via SSH_ASKPASS when needed
            if let pwd = password, !pwd.isEmpty {
                // Write a temporary askpass script
                let scriptPath = createAskPassScript(password: pwd)
                env["SSH_ASKPASS"] = scriptPath
                env["SSH_ASKPASS_REQUIRE"] = "prefer"
                env["DISPLAY"] = ":0"
            }
            process.environment = env

            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: SFTPError.connectionFailed(error.localizedDescription))
                return
            }

            // Write commands to stdin
            if let data = commands.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
                try? stdin.fileHandleForWriting.close()
            }

            process.terminationHandler = { _ in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outData, encoding: .utf8) ?? ""
                let errOutput = String(data: errData, encoding: .utf8) ?? ""

                let combined = output + errOutput
                if errOutput.lowercased().contains("permission denied") ||
                   errOutput.lowercased().contains("authentication failed") {
                    continuation.resume(throwing: SFTPError.authenticationFailed)
                } else if errOutput.lowercased().contains("connection refused") ||
                          errOutput.lowercased().contains("no route to host") ||
                          errOutput.lowercased().contains("could not resolve") {
                    continuation.resume(throwing: SFTPError.connectionFailed(errOutput))
                } else {
                    continuation.resume(returning: combined)
                }
            }
        }
    }

    // MARK: - Askpass script helper

    private func createAskPassScript(password: String) -> String {
        let escaped = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        let script = "#!/bin/sh\necho \"\(escaped)\"\n"
        let path = NSTemporaryDirectory() + "nexus_sftp_askpass_\(UUID().uuidString).sh"
        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        return path
    }

    // MARK: - Parse `ls -la` output

    func parseLsOutput(_ output: String, basePath: String) -> [SFTPItem] {
        var items: [SFTPItem] = []
        let normalizedBase = basePath.hasSuffix("/") ? basePath : basePath + "/"
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Skip "total N" lines, prompt lines, and header
            guard !trimmed.hasPrefix("total "),
                  !trimmed.hasPrefix("sftp>"),
                  !trimmed.hasPrefix("Connected to"),
                  !trimmed.hasPrefix("sftp: ") else { continue }

            if let item = parseLsLine(trimmed, basePath: normalizedBase) {
                // Skip . and ..
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
        // Split by whitespace, max 9 parts (last part = name, possibly with -> for symlinks)
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 9 else { return nil }

        let permStr = parts[0]
        // let linkCount = parts[1]  // not used
        let owner = parts[2]
        let group = parts[3]
        let sizeStr = parts[4]
        // Date: parts[5] (month), parts[6] (day), parts[7] (time/year)
        // Name: parts[8] onwards
        let nameParts = parts.dropFirst(8)
        var name = nameParts.joined(separator: " ")

        // Handle symlinks: "name -> target"
        var isSymlink = false
        if permStr.hasPrefix("l") {
            isSymlink = true
            if let arrowRange = name.range(of: " -> ") {
                name = String(name[..<arrowRange.lowerBound])
            }
        }

        let isDirectory = permStr.hasPrefix("d")
        let size = Int64(sizeStr) ?? 0
        let permissions = String(permStr.dropFirst()) // Remove type char

        // Parse date: "May 29 10:00" or "May 29 2024"
        let dateStr = "\(parts[5]) \(parts[6]) \(parts[7])"
        let modifiedDate = parseDate(dateStr) ?? Date()

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
        let formatWithTime = DateFormatter()
        formatWithTime.locale = Locale(identifier: "en_US_POSIX")
        formatWithTime.dateFormat = "MMM d HH:mm"

        let formatWithYear = DateFormatter()
        formatWithYear.locale = Locale(identifier: "en_US_POSIX")
        formatWithYear.dateFormat = "MMM d yyyy"

        return formatWithTime.date(from: str) ?? formatWithYear.date(from: str)
    }
}
