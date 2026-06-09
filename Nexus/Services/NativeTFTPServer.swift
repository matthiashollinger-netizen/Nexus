import Foundation
import Network

/// A self-contained TFTP server (RFC 1350) built on Network.framework — no external
/// tools. This is the server a Cisco/HP device connects to as a CLIENT to download
/// (RRQ) or upload (WRQ) files (IOS images, configs).
///
/// Supports octet (binary) and netascii modes, 512-byte blocks, read + write requests.
/// Port 69 needs root, so the UI defaults to a high port (6969).
final class NativeTFTPServer {

    private let rootDirectory: URL
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.hollinger.Nexus.tftp")

    var onLog: ((String) -> Void)?

    // TFTP opcodes
    private enum Op: UInt16 { case rrq = 1, wrq = 2, data = 3, ack = 4, error = 5 }
    private let blockSize = 512

    init?(rootDirectory: URL, port: Int) {
        guard port > 0, port <= 65535, let p = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        self.rootDirectory = rootDirectory
        self.port = p
    }

    // MARK: - Lifecycle

    func start() throws {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:  self?.onLog?("TFTP ready on UDP port \(self?.port.rawValue ?? 0), root \(self?.rootDirectory.path ?? "")")
            case .failed(let e): self?.onLog?("TFTP listener failed: \(e.localizedDescription)")
            default: break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Per-client connection

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        // The first datagram is the request (RRQ/WRQ).
        connection.receiveMessage { [weak self] data, _, _, _ in
            guard let self, let data else { connection.cancel(); return }
            self.handleRequest(data, on: connection)
        }
    }

    private func handleRequest(_ data: Data, on connection: NWConnection) {
        guard data.count >= 4 else { connection.cancel(); return }
        let opcode = UInt16(data[0]) << 8 | UInt16(data[1])

        // Parse "filename\0mode\0"
        let payload = data.subdata(in: 2..<data.count)
        let parts = payload.split(separator: 0x00, maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 1, let filename = String(data: Data(parts[0]), encoding: .utf8) else {
            sendError(4, "Illegal TFTP operation", on: connection); return
        }

        guard let safeURL = resolveSafePath(filename) else {
            sendError(2, "Access violation", on: connection)
            onLog?("DENIED path traversal: \(filename)")
            return
        }

        switch Op(rawValue: opcode) {
        case .rrq:
            onLog?("RRQ \(filename) → sending")
            startSendingFile(safeURL, filename: filename, on: connection)
        case .wrq:
            onLog?("WRQ \(filename) → receiving")
            startReceivingFile(safeURL, filename: filename, on: connection)
        default:
            sendError(4, "Illegal TFTP operation", on: connection)
        }
    }

    // MARK: - RRQ: send a file to the client

    private func startSendingFile(_ url: URL, filename: String, on connection: NWConnection) {
        guard let fileData = try? Data(contentsOf: url) else {
            sendError(1, "File not found", on: connection)
            onLog?("RRQ \(filename): not found")
            return
        }
        sendBlock(fileData, block: 1, filename: filename, on: connection)
    }

    private func sendBlock(_ fileData: Data, block: Int, filename: String, on connection: NWConnection) {
        let start = (block - 1) * blockSize
        guard start <= fileData.count else {
            onLog?("RRQ \(filename): complete (\(fileData.count) bytes)")
            connection.cancel(); return
        }
        let end = min(start + blockSize, fileData.count)
        let chunk = fileData.subdata(in: start..<end)

        var packet = Data()
        packet.append(contentsOf: [0x00, Op.data.rawValue.lowByte])  // opcode 3
        packet.append(contentsOf: UInt16(block & 0xFFFF).bytes)
        packet.append(chunk)

        connection.send(content: packet, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            // Wait for the ACK of this block, then send the next.
            connection.receiveMessage { [weak self] data, _, _, _ in
                guard let self else { return }
                guard let data, data.count >= 4 else { connection.cancel(); return }
                let op = UInt16(data[0]) << 8 | UInt16(data[1])
                let ackBlock = Int(UInt16(data[2]) << 8 | UInt16(data[3]))
                if op == Op.ack.rawValue && ackBlock == (block & 0xFFFF) {
                    if chunk.count < self.blockSize {
                        self.onLog?("RRQ \(filename): complete (\(fileData.count) bytes)")
                        connection.cancel()   // last (short) block ACKed → done
                    } else {
                        self.sendBlock(fileData, block: block + 1, filename: filename, on: connection)
                    }
                } else {
                    connection.cancel()
                }
            }
        })
    }

    // MARK: - WRQ: receive a file from the client

    private func startReceivingFile(_ url: URL, filename: String, on connection: NWConnection) {
        // ACK block 0 tells the client to start sending DATA block 1.
        sendAck(0, on: connection)
        receiveData(into: Data(), expecting: 1, url: url, filename: filename, on: connection)
    }

    private func receiveData(into accumulated: Data, expecting block: Int, url: URL,
                             filename: String, on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, _ in
            guard let self else { return }
            guard let data, data.count >= 4 else { connection.cancel(); return }
            let op = UInt16(data[0]) << 8 | UInt16(data[1])
            let blk = Int(UInt16(data[2]) << 8 | UInt16(data[3]))
            guard op == Op.data.rawValue, blk == (block & 0xFFFF) else {
                connection.cancel(); return
            }
            let chunk = data.subdata(in: 4..<data.count)
            var acc = accumulated
            acc.append(chunk)
            self.sendAck(block, on: connection)

            if chunk.count < self.blockSize {
                // Final block — write the file.
                do {
                    try acc.write(to: url, options: .atomic)
                    self.onLog?("WRQ \(filename): stored \(acc.count) bytes")
                } catch {
                    self.onLog?("WRQ \(filename): write failed — \(error.localizedDescription)")
                }
                connection.cancel()
            } else {
                self.receiveData(into: acc, expecting: block + 1, url: url, filename: filename, on: connection)
            }
        }
    }

    // MARK: - Helpers

    private func sendAck(_ block: Int, on connection: NWConnection) {
        var packet = Data([0x00, Op.ack.rawValue.lowByte])  // opcode 4
        packet.append(contentsOf: UInt16(block & 0xFFFF).bytes)
        connection.send(content: packet, completion: .idempotent)
    }

    private func sendError(_ code: UInt16, _ message: String, on connection: NWConnection) {
        var packet = Data([0x00, Op.error.rawValue.lowByte])  // opcode 5
        packet.append(contentsOf: code.bytes)
        packet.append(message.data(using: .utf8) ?? Data())
        packet.append(0x00)
        connection.send(content: packet, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Resolves a requested filename under the root, rejecting traversal outside it.
    func resolveSafePath(_ filename: String) -> URL? {
        let rootStd = rootDirectory.standardizedFileURL
        // TFTP filenames are usually bare names; strip any leading slash.
        var name = filename
        while name.hasPrefix("/") { name.removeFirst() }
        let candidate = rootStd.appendingPathComponent(name).standardizedFileURL
        let rootPath = rootStd.path.hasSuffix("/") ? rootStd.path : rootStd.path + "/"
        if candidate.path == rootStd.path || candidate.path.hasPrefix(rootPath) {
            return candidate
        }
        return nil
    }
}

// MARK: - Byte helpers

private extension UInt16 {
    var bytes: [UInt8] { [UInt8(self >> 8), UInt8(self & 0xFF)] }
    var lowByte: UInt8 { UInt8(self & 0xFF) }
}
