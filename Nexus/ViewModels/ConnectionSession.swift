import Foundation
import SwiftUI
import Network

enum ConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case disconnected
    case failed(String)
}

extension ConnectionSession {
    /// Maps a low-level NWError to a short, friendly, localized message instead of
    /// surfacing a raw technical error string to the user.
    nonisolated static func friendlyConnectionError(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED: return String(localized: "conn.error.refused")
            case .ETIMEDOUT:    return String(localized: "conn.error.timeout")
            case .EHOSTUNREACH, .ENETUNREACH: return String(localized: "conn.error.unreachable")
            case .ECONNRESET:   return String(localized: "conn.error.reset")
            default: break
            }
        case .dns:
            return String(localized: "conn.error.dns")
        default:
            break
        }
        // Fall back to the system-localized description (already user-readable).
        return error.localizedDescription
    }
}

@Observable
final class ConnectionSession: Identifiable {
    let id: UUID = UUID()
    let session: Session
    var state: ConnectionState = .idle {
        didSet { notifyIfUnexpectedlyDropped(from: oldValue) }
    }
    var title: String

    /// Set before a user-initiated `disconnect()` so the resulting `.disconnected`
    /// state does NOT fire a "connection lost" notification.
    private var isClosing = false

    // SSH parameters (resolved at init)
    var sshArgs: [String] = []
    var sshPassword: String? = nil
    var tempKeyPath: String? = nil
    /// true = session has no stored credential → offer "save credentials" sheet after login
    var shouldOfferCredentialSave: Bool = false
    /// Prevents the save-offer from showing more than once per session
    var credentialSaveOffered: Bool = false
    /// Password captured from terminal input when no credential is stored
    var capturedPassword: String = ""

    // RDP — resolved separately in AppViewModel.connect() from rdpCredentialId
    var rdpPassword: String? = nil

    // Telnet
    var telnetService: TelnetService?

    // Serial
    var serialService: SerialService?

    // Terminal data bridge for non-SSH connections
    var terminalSendHandler: (([UInt8]) -> Void)?
    var terminalReceiveCallback: (([UInt8]) -> Void)? = nil

    /// Weak reference to the live NSView — set by the terminal view on init.
    /// Used to reliably give keyboard focus when switching tabs.
    weak var terminalNSView: NSView?

    init(session: Session, credential: Credential?, settings: AppSettings) {
        self.session = session
        self.title = session.name.isEmpty ? session.host : session.name

        switch session.connectionType {
        case .ssh:
            setupSSH(credential: credential, settings: settings)
        case .telnet, .serial, .rdp:
            break
        }
    }

    private func setupSSH(credential: Credential?, settings: AppSettings) {
        let useLegacy = session.sshUseLegacyAlgorithms ?? settings.sshLegacyAlgorithms

        var keyPath: String? = nil

        // Private key from credential
        if let pk = credential?.privateKey, !pk.isEmpty {
            keyPath = try? SSHArgumentBuilder.writeTempPrivateKey(pk)
            tempKeyPath = keyPath
        } else if !session.sshPrivateKeyPath.isEmpty {
            keyPath = session.sshPrivateKeyPath
        }

        var builder = SSHArgumentBuilder(
            host: session.host,
            port: session.port,
            username: session.username,
            privateKeyPath: keyPath,
            useLegacyAlgorithms: useLegacy,
            strictHostKeyChecking: session.sshStrictHostKeyChecking
        )
        builder.jumpHost        = session.jumpHost
        builder.portForwardings = session.portForwardings
        builder.socks5Proxy     = session.socks5Proxy
        builder.connectTimeout  = session.connectTimeout
        sshArgs = builder.build()
        sshPassword = credential?.password
        // No credential linked → offer to save after successful login
        credentialSaveOffered = (credential != nil)
    }

    // MARK: - Telnet

    func connectTelnet() {
        state = .connecting
        let svc = TelnetService()
        svc.onStateChange = { [weak self] nwState in
            guard let self else { return }
            if case .ready = nwState {
                self.state = .connected
            } else if case .failed(let err) = nwState {
                self.state = .failed(Self.friendlyConnectionError(err))
            } else if case .cancelled = nwState {
                self.state = .disconnected
            }
        }
        svc.onReceive = { [weak self] bytes in
            self?.terminalReceiveCallback?(bytes)
        }
        svc.connect(host: session.host, port: session.port)
        self.telnetService = svc
        terminalSendHandler = { [weak svc] bytes in svc?.send(bytes) }
    }

    // MARK: - Serial

    func connectSerial() {
        state = .connecting
        let svc = SerialService()
        svc.onStateChange = { [weak self] s in
            guard let self else { return }
            switch s {
            case .connected: self.state = .connected
            case .disconnected: self.state = .disconnected
            case .error(let msg): self.state = .failed(msg)
            }
        }
        svc.onReceive = { [weak self] bytes in
            self?.terminalReceiveCallback?(bytes)
        }
        svc.connect(
            port: session.serialPort,
            baudRate: session.serialBaudRate,
            dataBits: session.serialDataBits,
            stopBits: session.serialStopBits,
            parity: session.serialParity,
            flowControl: session.serialFlowControl
        )
        self.serialService = svc
        terminalSendHandler = { [weak svc] bytes in svc?.send(bytes) }
    }

    // MARK: - Disconnect

    /// Posts a macOS notification when a *live* session drops without the user
    /// closing it. `.failed` always notifies; `.disconnected` only when it wasn't
    /// a user-initiated close.
    private func notifyIfUnexpectedlyDropped(from old: ConnectionState) {
        // Only an ESTABLISHED session counts — a failed connect attempt (still
        // `.connecting`) is shown by the reconnect overlay and must not notify.
        let wasLive: Bool = { if case .connected = old { return true }; return false }()
        guard wasLive else { return }
        switch state {
        case .failed(let msg):
            NotificationService.shared.sessionDropped(name: title, failed: true, reason: msg)
        case .disconnected where !isClosing:
            NotificationService.shared.sessionDropped(name: title, failed: false, reason: nil)
        default:
            break
        }
    }

    func disconnect() {
        isClosing = true
        telnetService?.disconnect()
        serialService?.disconnect()
        if let path = tempKeyPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        // Clean up SSH_ASKPASS keychain slot
        NexusAskPassService.cleanup(token: id.uuidString)
        state = .disconnected
    }

    /// Plain title — the live `StatusDot` in the tab now carries the state, so the
    /// title no longer needs the "…"/"✕" emoji suffixes.
    var tabTitle: String { title }
}
