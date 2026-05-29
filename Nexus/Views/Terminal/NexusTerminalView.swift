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
        case .rdp:
            return NexusRDPTerminalView(cs: cs)
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Font updates only — focus is managed by TabItemView.onTapGesture
        // and viewDidMoveToWindow on the NSView subclasses.
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
    private var capturingPassword = false
    private var captureBuffer = ""
    private var keyMonitor: Any?
    private let highlighter = TerminalHighlighter.shared

    init(cs: ConnectionSession, fontName: String, fontSize: Double) {
        self.cs = cs
        super.init(frame: .zero)
        // Store weak reference so TabItemView can give us keyboard focus on tab switch
        cs.terminalNSView = self
        let f = NSFont(name: fontName, size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        self.font = f
        startSSH()
        installKeyMonitor()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    // Auto-focus when first added to a window (new connection opened)
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }

    private func startSSH() {
        guard !cs.session.host.isEmpty else {
            cs.state = .failed("Kein Hostname konfiguriert")
            return
        }
        cs.state = .connecting

        // Build environment: start with current process env, then inject SSH_ASKPASS
        var envDict = ProcessInfo.processInfo.environment
        let token = cs.id.uuidString

        if let pwd = cs.sshPassword, !pwd.isEmpty {
            // Store password in temp keychain slot for the askpass helper
            NexusAskPassService.storePassword(pwd, token: token)
            if let askpassEnv = NexusAskPassService.environment(token: token) {
                envDict.merge(askpassEnv) { _, new in new }
            }
        }

        // Convert to "KEY=VALUE" array expected by SwiftTerm
        let envArray = envDict.map { "\($0.key)=\($0.value)" }

        startProcess(executable: "/usr/bin/ssh", args: cs.sshArgs, environment: envArray)
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
        guard let eventWindow = event.window, eventWindow === self.window else { return }

        if event.modifierFlags.contains(.command) && event.keyCode == 9 {
            if let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
                captureBuffer = pasted.components(separatedBy: .newlines).joined()
            }
            return
        }

        switch event.keyCode {
        case 36, 76:
            let pwd = captureBuffer
            captureBuffer = ""
            capturingPassword = false
            DispatchQueue.main.async { [weak self] in self?.cs.capturedPassword = pwd }
        case 51, 117:
            if !captureBuffer.isEmpty { captureBuffer.removeLast() }
        default:
            if let chars = event.characters,
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                captureBuffer += chars.filter { ($0.asciiValue ?? 0) >= 32 }
            }
        }
    }

    // MARK: - Override LocalProcessTerminalView hooks

    override func dataReceived(slice: ArraySlice<UInt8>) {
        // Detect on original text before highlighting
        let originalBytes = Array(slice)
        let text = String(bytes: originalBytes, encoding: .utf8) ?? ""
        let lower = text.lowercased()

        // Feed highlighted bytes to the terminal
        let highlighted = highlighter.process(originalBytes)
        super.dataReceived(slice: ArraySlice(highlighted))

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

        // Capture typed password for SaveCredentialsSheet
        if cs.sshPassword == nil && !cs.credentialSaveOffered {
            if lower.contains("password:") {
                capturingPassword = true
                captureBuffer = ""
                DispatchQueue.main.async { [weak self] in self?.cs.capturedPassword = "" }
            }
        }

        // Detect shell prompt → offer save credentials
        if !cs.credentialSaveOffered {
            let lines = text.components(separatedBy: .newlines)
            let hasPrompt = lines.contains { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty &&
                    (t.hasSuffix("$ ") || t.hasSuffix("# ") ||
                     t.hasSuffix("% ") || t.hasSuffix("> ") ||
                     t.last == "$" || t.last == "#" || t.last == "%")
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
        DispatchQueue.main.async { [weak self] in self?.cs.state = .disconnected }
    }
}

// MARK: - Network / Serial terminal (TerminalView + external data source)

final class NexusNetTerminalView: TerminalView, TerminalViewDelegate {
    private let cs: ConnectionSession
    private let highlighter = TerminalHighlighter.shared

    init(cs: ConnectionSession, fontName: String, fontSize: Double) {
        self.cs = cs
        super.init(frame: .zero)
        // Store weak reference so TabItemView can give us keyboard focus on tab switch
        cs.terminalNSView = self
        let f = NSFont(name: fontName, size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        self.font = f
        self.terminalDelegate = self
        startConnection()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Auto-focus when first added to a window (new connection opened)
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }

    private func startConnection() {
        cs.terminalReceiveCallback = { [weak self] bytes in
            guard let self else { return }
            // Apply highlighting before feeding to the terminal
            let highlighted = self.highlighter.process(bytes)
            self.feed(byteArray: ArraySlice(highlighted))
        }
        switch cs.session.connectionType {
        case .telnet: cs.connectTelnet()
        case .serial: cs.connectSerial()
        default: break
        }
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) { cs.terminalSendHandler?(Array(data)) }
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

// MARK: - RDP View (Feature 8)

final class NexusRDPTerminalView: NSView {
    let cs: ConnectionSession
    var rdpProcess: Process?

    private let statusLabel = NSTextField(labelWithString: "")
    private let reconnectButton = NSButton(title: "", target: nil, action: nil)

    init(cs: ConnectionSession) {
        self.cs = cs
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1).cgColor
        cs.terminalNSView = self
        setupUI()
        startRDP()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { stopRDP() }

    private func setupUI() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.alignment = .center
        addSubview(statusLabel)

        reconnectButton.translatesAutoresizingMaskIntoConstraints = false
        reconnectButton.title = String(localized: "rdp.reconnect")
        reconnectButton.bezelStyle = .rounded
        reconnectButton.isHidden = true
        reconnectButton.target = self
        reconnectButton.action = #selector(reconnectTapped)
        addSubview(reconnectButton)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            reconnectButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            reconnectButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16)
        ])
    }

    func startRDP() {
        guard let xfreerdp = findXFreeRDP() else {
            showInstallInstructions()
            return
        }

        let session = cs.session
        var args: [String] = []
        args += ["/v:\(session.host)"]

        let user = session.rdpUsername.isEmpty ? session.username : session.rdpUsername
        if !user.isEmpty { args += ["/u:\(user)"] }

        if !session.rdpDomain.isEmpty { args += ["/d:\(session.rdpDomain)"] }

        // Password from credential
        if let pwd = cs.sshPassword, !pwd.isEmpty {
            args += ["/p:\(pwd)"]
        }

        args += ["/w:\(session.rdpWidth)", "/h:\(session.rdpHeight)"]
        args += ["/bpp:\(session.rdpColorDepth)"]

        if session.rdpClipboardSharing { args += ["+clipboard"] }
        if session.rdpDriveRedirection { args += ["+drives"] }
        if session.rdpFullscreen       { args += ["/f"] }

        args += ["/dynamic-resolution", "/cert:ignore"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xfreerdp)
        process.arguments = args
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.cs.state = .disconnected
                self?.statusLabel.stringValue = String(localized: "connection.terminated")
                self?.reconnectButton.isHidden = false
            }
        }

        do {
            try process.run()
            rdpProcess = process
            cs.state = .connected
            statusLabel.stringValue = String(localized: "rdp.connecting")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if self?.cs.state == .connected {
                    self?.statusLabel.stringValue = String(localized: "rdp.status")
                    + ": " + String(localized: "server.status.running")
                }
            }
        } catch {
            cs.state = .failed(error.localizedDescription)
            statusLabel.stringValue = error.localizedDescription
        }
    }

    func stopRDP() {
        rdpProcess?.terminate()
        rdpProcess = nil
    }

    private func findXFreeRDP() -> String? {
        let candidates = [
            "/opt/homebrew/bin/xfreerdp3",
            "/opt/homebrew/bin/xfreerdp",
            "/usr/local/bin/xfreerdp3",
            "/usr/local/bin/xfreerdp"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func showInstallInstructions() {
        cs.state = .failed("FreeRDP not installed")
        subviews.forEach { $0.removeFromSuperview() }

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "desktopcomputer.trianglebadge.exclamationmark",
                                              accessibilityDescription: nil) ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentTintColor = .systemOrange
        icon.setContentHuggingPriority(.defaultHigh, for: .vertical)
        let iconSize = NSLayoutConstraint(item: icon, attribute: .width, relatedBy: .equal,
                                          toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 48)
        let iconH = NSLayoutConstraint(item: icon, attribute: .height, relatedBy: .equal,
                                        toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 48)
        icon.addConstraints([iconSize, iconH])

        let label = NSTextField(labelWithString: String(localized: "rdp.install_hint"))
        label.font = NSFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        let brewLabel = NSTextField(labelWithString: String(localized: "rdp.install_brew"))
        brewLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        brewLabel.textColor = .systemGreen
        brewLabel.alignment = .center

        let copyBtn = NSButton(title: String(localized: "rdp.copy_command"), target: self, action: #selector(copyBrewCommand))
        copyBtn.bezelStyle = .rounded

        container.addArrangedSubview(icon)
        container.addArrangedSubview(label)
        container.addArrangedSubview(brewLabel)
        container.addArrangedSubview(copyBtn)

        addSubview(container)
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @objc private func copyBrewCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install freerdp", forType: .string)
    }

    @objc private func reconnectTapped() {
        reconnectButton.isHidden = true
        stopRDP()
        startRDP()
    }
}
