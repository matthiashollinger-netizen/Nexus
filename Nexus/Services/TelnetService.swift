import Foundation
import Network

/// Manages a raw TCP (Telnet) connection.
/// Callers set `onReceive` to get incoming bytes and call `send(_:)` to write.
final class TelnetService {
    private var connection: NWConnection?
    var onReceive: (([UInt8]) -> Void)?
    var onStateChange: ((NWConnection.State) -> Void)?

    func connect(host: String, port: Int) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
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
