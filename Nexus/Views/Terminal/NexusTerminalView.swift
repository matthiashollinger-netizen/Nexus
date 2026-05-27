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

    init(cs: ConnectionSession, fontName: String, fontSize: Double) {
        self.cs = cs
        super.init(frame: .zero)
        let f = NSFont(name: fontName, size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        self.font = f
        startSSH()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startSSH() {
        cs.state = .connecting
        startProcess(executable: "/usr/bin/ssh", args: cs.sshArgs)
        cs.state = .connected
    }

    // MARK: - Override LocalProcessTerminalView hooks

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)

        // Auto-send stored password on password prompt
        if !passwordSent, let pwd = cs.sshPassword {
            let text = String(bytes: slice, encoding: .utf8) ?? ""
            let lower = text.lowercased()
            if lower.contains("password:") || lower.contains("passphrase for key") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self, !self.passwordSent else { return }
                    self.send(txt: pwd + "\r")
                    self.passwordSent = true
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
