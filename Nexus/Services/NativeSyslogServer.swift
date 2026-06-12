import Foundation
import Network

/// A self-contained syslog collector on Network.framework's UDP listener — the
/// piece network engineers reach for during a firmware push: point the switch's
/// `logging host <mac-ip>` at it and watch the device talk. Parses RFC 3164 and
/// RFC 5424. No external daemon, no root if a high port (e.g. 5514) is used
/// (binding ≤1024 needs privileges; 514 only works when allowed).
@Observable
final class NativeSyslogServer {

    /// Live ring buffer of received messages (newest last), capped to stay light.
    private(set) var entries: [SyslogEntry] = []
    private let maxEntries = 2000

    @ObservationIgnored var onLog: ((String) -> Void)?
    @ObservationIgnored private let port: NWEndpoint.Port
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private let queue = DispatchQueue(label: "com.hollinger.Nexus.syslog")

    /// Number of messages at error severity or worse since start.
    private(set) var alertCount = 0

    init?(port: Int) {
        guard port > 0, port <= 65535, let p = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        self.port = p
    }

    func start() throws {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(on: connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:   self?.onLog?("Syslog listening on UDP \(self?.port.rawValue ?? 0)")
            case .failed(let e): self?.onLog?("Listener failed: \(e.localizedDescription)")
            default: break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func clear() {
        entries.removeAll()
        alertCount = 0
    }

    // MARK: - Receiving

    private func receive(on connection: NWConnection) {
        connection.start(queue: queue)
        receiveNext(connection)
    }

    private func receiveNext(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { connection.cancel(); return }
            if let data, !data.isEmpty {
                let raw = String(decoding: data, as: UTF8.self)
                let ip = Self.remoteIP(of: connection)
                let entry = SyslogEntry.parse(raw, sourceIP: ip, now: Date())
                DispatchQueue.main.async { self.append(entry) }
            }
            if error == nil {
                self.receiveNext(connection)   // keep listening on this endpoint
            } else {
                connection.cancel()
            }
        }
    }

    private func append(_ entry: SyslogEntry) {
        entries.append(entry)
        if entry.severity.isAlert { alertCount += 1 }
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    // MARK: - CSV export

    /// Writes all current entries to a CSV at `url`.
    func exportCSV(to url: URL) throws {
        let df = ISO8601DateFormatter()
        var csv = "received,device_time,source_ip,severity,facility,hostname,tag,message\n"
        for e in entries {
            let dev = e.deviceTimestamp.map { df.string(from: $0) } ?? ""
            let msg = e.message.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(df.string(from: e.receivedAt)),\(dev),\(e.sourceIP),\(e.severity.keyword),\(e.facility),\(e.hostname),\(e.tag),\"\(msg)\"\n"
        }
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func remoteIP(of connection: NWConnection) -> String {
        if case let .hostPort(host, _) = connection.endpoint {
            switch host {
            case .ipv4(let a): return "\(a)".components(separatedBy: "%").first ?? "\(a)"
            case .ipv6(let a): return "\(a)".components(separatedBy: "%").first ?? "\(a)"
            case .name(let n, _): return n
            @unknown default: return "?"
            }
        }
        return "?"
    }
}
