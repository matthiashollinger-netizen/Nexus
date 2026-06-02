import Foundation
import Network

/// A minimal, self-contained static-file HTTP/1.1 server built on Network.framework.
/// Replaces the previous `python3 -m http.server` dependency — modern macOS no
/// longer ships python3, so the native server is required for a no-install app.
///
/// Serves GET/HEAD for files under `rootDirectory`, with directory listing for
/// folders (or index.html if present). Path traversal outside the root is blocked.
final class NativeHTTPServer {

    private let rootDirectory: URL
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.hollinger.Nexus.httpserver")

    /// Called with human-readable log lines (request lines, errors).
    var onLog: ((String) -> Void)?

    init?(rootDirectory: URL, port: Int) {
        guard let p = NWEndpoint.Port(rawValue: UInt16(truncatingIfNeeded: port)), port > 0 else { return nil }
        self.rootDirectory = rootDirectory
        self.port = p
    }

    // MARK: - Lifecycle

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onLog?("Serving \(self?.rootDirectory.path ?? "") on port \(self?.port.rawValue ?? 0)")
            case .failed(let error):
                self?.onLog?("Listener failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }

            // Wait until we have the full header block (terminated by CRLF CRLF).
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer[..<headerEnd.lowerBound]
                self.respond(to: headerData, on: connection)
            } else if isComplete || error != nil || buffer.count > 1_000_000 {
                self.sendResponse(status: "400 Bad Request", contentType: "text/plain",
                                  body: Data("Bad Request".utf8), on: connection, headOnly: false)
            } else {
                self.receiveRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to headerData: Data, on connection: NWConnection) {
        guard let header = String(data: headerData, encoding: .utf8),
              let requestLine = header.components(separatedBy: "\r\n").first else {
            sendResponse(status: "400 Bad Request", contentType: "text/plain",
                         body: Data("Bad Request".utf8), on: connection, headOnly: false)
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(status: "400 Bad Request", contentType: "text/plain",
                         body: Data("Bad Request".utf8), on: connection, headOnly: false)
            return
        }
        let method = parts[0].uppercased()
        let rawPath = parts[1]
        onLog?("\(method) \(rawPath)")

        guard method == "GET" || method == "HEAD" else {
            sendResponse(status: "405 Method Not Allowed", contentType: "text/plain",
                         body: Data("Method Not Allowed".utf8), on: connection, headOnly: false)
            return
        }
        let headOnly = (method == "HEAD")

        // Strip query string, percent-decode.
        let pathOnly = rawPath.components(separatedBy: "?").first ?? rawPath
        let decoded = pathOnly.removingPercentEncoding ?? pathOnly

        guard let target = resolveSafePath(decoded) else {
            sendResponse(status: "403 Forbidden", contentType: "text/plain",
                         body: Data("Forbidden".utf8), on: connection, headOnly: headOnly)
            return
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) else {
            sendResponse(status: "404 Not Found", contentType: "text/plain",
                         body: Data("Not Found".utf8), on: connection, headOnly: headOnly)
            return
        }

        if isDir.boolValue {
            // Prefer index.html, else generate a listing.
            let index = target.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: index.path) {
                serveFile(index, on: connection, headOnly: headOnly)
            } else {
                serveDirectoryListing(target, requestPath: decoded, on: connection, headOnly: headOnly)
            }
        } else {
            serveFile(target, on: connection, headOnly: headOnly)
        }
    }

    // MARK: - Path safety

    /// Resolves `requestPath` under the root and rejects traversal outside it.
    private func resolveSafePath(_ requestPath: String) -> URL? {
        let rootStd = rootDirectory.standardizedFileURL
        var relative = requestPath
        if relative.hasPrefix("/") { relative.removeFirst() }
        let candidate = rootStd.appendingPathComponent(relative).standardizedFileURL
        // The resolved path must remain within the root directory.
        let rootPath = rootStd.path.hasSuffix("/") ? rootStd.path : rootStd.path + "/"
        if candidate.path == rootStd.path || candidate.path.hasPrefix(rootPath) {
            return candidate
        }
        return nil
    }

    // MARK: - Responses

    private func serveFile(_ url: URL, on connection: NWConnection, headOnly: Bool) {
        guard let data = try? Data(contentsOf: url) else {
            sendResponse(status: "404 Not Found", contentType: "text/plain",
                         body: Data("Not Found".utf8), on: connection, headOnly: headOnly)
            return
        }
        sendResponse(status: "200 OK", contentType: Self.mimeType(for: url),
                     body: data, on: connection, headOnly: headOnly)
    }

    private func serveDirectoryListing(_ dir: URL, requestPath: String, on connection: NWConnection, headOnly: Bool) {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let base = requestPath.hasSuffix("/") ? requestPath : requestPath + "/"
        var html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Index of \(requestPath)</title></head><body>"
        html += "<h1>Index of \(requestPath)</h1><ul>"
        for entry in entries.sorted() {
            let escaped = entry.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry
            html += "<li><a href=\"\(base)\(escaped)\">\(entry)</a></li>"
        }
        html += "</ul></body></html>"
        sendResponse(status: "200 OK", contentType: "text/html; charset=utf-8",
                     body: Data(html.utf8), on: connection, headOnly: headOnly)
    }

    private func sendResponse(status: String, contentType: String, body: Data,
                              on connection: NWConnection, headOnly: Bool) {
        var headers = "HTTP/1.1 \(status)\r\n"
        headers += "Content-Type: \(contentType)\r\n"
        headers += "Content-Length: \(body.count)\r\n"
        headers += "Connection: close\r\n"
        headers += "Server: Nexus\r\n\r\n"

        var response = Data(headers.utf8)
        if !headOnly { response.append(body) }

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - MIME types

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "js":          return "application/javascript; charset=utf-8"
        case "json":        return "application/json; charset=utf-8"
        case "txt", "log", "cfg", "conf": return "text/plain; charset=utf-8"
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":  return "image/gif"
        case "svg":  return "image/svg+xml"
        case "pdf":  return "application/pdf"
        case "xml":  return "application/xml"
        case "zip":  return "application/zip"
        case "bin", "img", "tftp": return "application/octet-stream"
        default:     return "application/octet-stream"
        }
    }
}
