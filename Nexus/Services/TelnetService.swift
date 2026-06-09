import Foundation
import Network

/// Manages a raw TCP (Telnet) connection.
/// Callers set `onReceive` to get incoming bytes and call `send(_:)` to write.
final class TelnetService {
    private var connection: NWConnection?
    var onReceive: (([UInt8]) -> Void)?
    var onStateChange: ((NWConnection.State) -> Void)?

    func connect(host: String, port: Int) {
        // `UInt16(port)` TRAPS on overflow — a user-entered port like 70000 (or 0)
        // would crash the app. Validate the range and surface a clean failure instead.
        guard port > 0, port <= 65535, let port16 = UInt16(exactly: port),
              let nwPort = NWEndpoint.Port(rawValue: port16) else {
            onStateChange?(.failed(.posix(.EINVAL)))
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let conn = NWConnection(to: endpoint, using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async { self?.onStateChange?(state) }
        }

        conn.start(queue: .global(qos: .userInitiated))
        receiveLoop(conn)
    }

    func send(_ bytes: [UInt8]) {
        connection?.send(content: Data(bytes), completion: .idempotent)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    // MARK: - Private

    private func receiveLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                let bytes = [UInt8](data)
                DispatchQueue.main.async { self?.onReceive?(bytes) }
            }
            if !isComplete, error == nil {
                self?.receiveLoop(conn)
            }
        }
    }
}
