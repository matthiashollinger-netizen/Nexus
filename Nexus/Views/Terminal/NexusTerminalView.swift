import SwiftUI
import SwiftTerm
import AppKit

// MARK: - SwiftUI wrapper

struct NexusTerminalView: NSViewRepresentable {
    let cs: ConnectionSession
    let fontName: String
    let fontSize: Double

    func makeNSView(context: Context) -> NSView {
        switch cs.session.connectionType {
        case .ssh:
            return NexusSSHTerminalView(cs: cs, fontName: fontName, fontSize: fontSize)
        case .telnet, .serial:
            return NexusNetTerminalView(cs: cs, fontName: fontName, fontSize: fontSize)
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let f = resolvedFont(name: fontName, size: fontSize)
        if let ssh = nsView as? NexusSSHTerminalView { ssh.font = f }
        if let net = nsView as? NexusNetTerminalView { net.font = f }
    }

    private func resolvedFont(name: String, size: Double) -> NSFont {
        NSFont(name: name, size: CGFloat(size)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }
}

// MARK: - SSH terminal (subclass of LocalProcessTerminalView)

final class NexusSSHTerminalView: LocalProcessTerminalView {
    private let cs: ConnectionSession
    private var passwordSent = false
    /// Whether we are currently buffering keystrokes for the password capture
    private var capturingPassword = false
    private var captureBuffer = ""
    /// NSEvent local monitor — installed to capture password keystrokes
    private var keyMonitor: Any?

    init(cs: ConnectionSession, fontName: String, fontSize: Double) {
        self.cs = cs
        super.init(frame: .zero)
        let f = NSFont(name: fontName, size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        self.font = f
        startSSH()
        installKeyMonitor()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    private func startSSH() {
        cs.state = .connecting
        startProcess(executable: "/usr/bin/ssh", args: cs.sshArgs)
        cs.state = .connected
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleCaptureKey(event)
            return event    // always pass through so terminal still receives it
        }
    }

    private func handleCaptureKey(_ event: NSEvent) {
        guard capturingPassword else { return }
        // Only capture events from our window
        guard let eventWindow = event.window, eventWindow === self.window else { return }

        switch event.keyCode {
        case 36, 76:   // Return / numpad Enter — password done
            let pwd = captureBuffer
            captureBuffer = ""
            capturingPassword = false
            DispatchQueue.main.async { [weak self] in
                self?.cs.capturedPassword = pwd
            }
        case 51, 117:  // Backspace / Delete
            if !captureBuffer.isEmpty { captureBuffer.removeLast() }
        default:
            if let chars = event.characters {
                // Accept printable characters only
                captureBuffer += chars.filter { ($0.asciiValue ?? 0) >= 32 }
            }
        }
    }

    // MARK: - Override LocalProcessTerminalView hooks

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)

        let text = String(bytes: slice, encoding: .utf8) ?? ""
        let lower = text.lowercased()

        // Auto-send stored password on password prompt
        if !passwordSent, let pwd = cs.sshPassword {
            if lower.contains("password:") || lower.contains("passphrase for key") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self, !self.passwordSent else { return }
                    self.send(txt: pwd + "\r")
                    self.passwordSent = true
                }
            }
        }

        // If no credential linked → capture what the user types at the password prompt
        // so SaveCredentialsSheet can pre-fill it
        if cs.sshPassword == nil && !cs.credentialSaveOffered {
            if lower.contains("password:") {
                capturingPassword = true
                captureBuffer = ""
                DispatchQueue.main.async { [weak self] in
                    self?.cs.capturedPassword = ""
                }
            }
        }

        // Detect shell prompt → offer "save credentials?" if no credential linked
        if !cs.credentialSaveOffered {
            // Common prompt endings: "$ ", "# ", "% ", "> "
            let lines = text.components(separatedBy: .newlines)
            let hasPrompt = lines.contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty &&
                    (trimmed.hasSuffix("$ ") || trimmed.hasSuffix("# ") ||
                     trimmed.hasSuffix("% ") || trimmed.hasSuffix("> ") ||
                     trimmed.last == "$" || trimmed.last == "#" || trimmed.last == "%")
            }
            if hasPrompt {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.cs.credentialSaveOffered = true
                    self.cs.shouldOfferCredentialSave = true
                }
            }
        }
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            self?.cs.state = .disconnected
        }
    }
}

// MARK: - Network / Serial terminal (TerminalView + external data source)

final class NexusNetTerminalView: TerminalView, TerminalViewDelegate {
    private let cs: ConnectionSession

    init(cs: ConnectionSession, fontName: String, fontSize: Double) {
        self.cs = cs
        super.init(frame: .zero)
        let f = NSFont(name: fontName, size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        self.font = f
        self.terminalDelegate = self
        startConnection()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startConnection() {
        cs.terminalReceiveCallback = { [weak self] bytes in
            self?.feed(byteArray: ArraySlice(bytes))
        }
        switch cs.session.connectionType {
        case .telnet: cs.connectTelnet()
        case .serial: cs.connectSerial()
        default: break
        }
    }

    // MARK: - TerminalViewDelegate (required)

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        cs.terminalSendHandler?(Array(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: TerminalView, title: String) {
        DispatchQueue.main.async { [weak self] in self?.cs.title = title }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func clipboardCopy(source: TerminalView, content: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(content, forType: .string)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
