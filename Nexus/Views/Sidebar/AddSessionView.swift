import SwiftUI

struct AddSessionView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    var existingSession: Session?
    var parentFolderId: UUID?

    @State private var draft: Session
    // Quick-entry credential — username comes from draft.username (Basic section)
    @State private var quickPassword: String = ""
    @State private var useQuickCredential: Bool = false

    // Advanced section expansion state
    @State private var expandSecurity = false
    @State private var expandGateway  = false
    @State private var expandTerminal = false
    @State private var expandBehaviour = false
    @State private var expandSerialParams = false

    init(session: Session? = nil, parentFolderId: UUID? = nil) {
        self.existingSession = session
        self.parentFolderId = parentFolderId
        if let s = session {
            _draft = State(initialValue: s)
        } else {
            var s = Session()
            s.folderId = parentFolderId
            _draft = State(initialValue: s)
        }
    }

    private var isEditing: Bool { existingSession != nil }
    private var title: String { isEditing ? String(localized: "session.edit") : String(localized: "session.new") }

    /// Live validation: host required for SSH/Telnet, serial port required for Serial.
    private var isValid: Bool {
        switch draft.connectionType {
        case .serial: return !draft.serialPort.isEmpty
        case .ssh, .telnet, .rdp: return !draft.host.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Protocol icon bar (MobaXterm-style) ──────────────────────────
            ProtocolBar(selected: $draft.connectionType, onChange: applyProtocolDefaults)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()

            // ── Scrollable settings ──────────────────────────────────────────
            Form {
                basicSection
                advancedSections
                bottomSection
            }
            .formStyle(.grouped)

            Divider()

            // ── Footer ───────────────────────────────────────────────────────
            HStack(spacing: 12) {
                if !isValid {
                    Label(validationHint, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("action.cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("action.save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 560, minHeight: 620)
        .onAppear {
            // Auto-expand advanced groups that already hold values.
            if draft.sshUseLegacyAlgorithms == true || draft.sshStrictHostKeyChecking
                || !draft.sshPrivateKeyPath.isEmpty { expandSecurity = true }
            if draft.jumpHost != nil || !draft.portForwardings.isEmpty
                || (draft.socks5Proxy?.enabled ?? false) { expandGateway = true }
            if draft.themeId != nil || draft.terminalFontSize != nil
                || draft.highlightRuleset != nil { expandTerminal = true }
            if draft.macroOnConnectId != nil || draft.autoConnectOnLaunch { expandBehaviour = true }
            // Clear a dangling credential reference (avoids invalid-Picker warning).
            if let cid = draft.credentialId,
               !vm.credentials.contains(where: { $0.id == cid }) {
                draft.credentialId = nil
            }
        }
    }

    private var validationHint: String {
        draft.connectionType == .serial
            ? String(localized: "session.validation.serial_port")
            : String(localized: "session.validation.host")
    }

    // MARK: - Basic settings (per protocol, prominent)

    @ViewBuilder private var basicSection: some View {
        Section {
            switch draft.connectionType {
            case .ssh, .telnet:
                LabeledContent("session.host") {
                    TextField("", text: $draft.host)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .overlay(invalidBorder(when: draft.host.trimmingCharacters(in: .whitespaces).isEmpty))
                }
                LabeledContent("session.port") {
                    TextField("", value: $draft.port, format: .number)
                        .frame(width: 90)
                        .textFieldStyle(.roundedBorder)
                }
                if draft.connectionType == .ssh {
                    LabeledContent("session.username") {
                        TextField("", text: $draft.username)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                    }
                    credentialField
                }

            case .serial:
                SerialBasicFields(draft: $draft)

            case .rdp:
                LabeledContent("session.host") {
                    TextField("", text: $draft.host)
                        .textFieldStyle(.roundedBorder)
                }
            }
        } header: {
            Text("session.basic")
        }
    }

    @ViewBuilder private var credentialField: some View {
        if let credName = linkedCredentialName {
            LabeledContent("session.pwgroup") {
                HStack {
                    Image(systemName: "key.fill").foregroundStyle(.secondary)
                    Text(credName)
                    Spacer()
                    Button("action.change") { draft.credentialId = nil }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .font(.callout)
                }
            }
        } else {
            LabeledContent("session.pwgroup") {
                PasswordGroupPicker(selectedId: $draft.credentialId)
                    .labelsHidden()
                    .onChange(of: draft.credentialId) { _, newVal in
                        if newVal != nil { useQuickCredential = false }
                    }
            }
            Toggle("session.credential.enter_now", isOn: $useQuickCredential)
                .onChange(of: useQuickCredential) { _, on in if on { draft.credentialId = nil } }
            if useQuickCredential {
                LabeledContent("cred.password") {
                    SecureField("", text: $quickPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var linkedCredentialName: String? {
        guard let cid = draft.credentialId else { return nil }
        let cred = vm.credentials.first { $0.id == cid }
        return cred?.name.isEmpty == false ? cred?.name : cred?.username
    }

    // MARK: - Advanced disclosure groups

    @ViewBuilder private var advancedSections: some View {
        // 1. Verbindung & Sicherheit (SSH only)
        if draft.connectionType == .ssh {
            Section {
                DisclosureGroup(isExpanded: $expandSecurity) {
                    SecurityControls(draft: $draft)
                } label: {
                    advancedLabel("session.adv.security", systemImage: "lock.shield")
                }
            }
            // 2. Gateway & Tunneling (SSH only)
            Section {
                DisclosureGroup(isExpanded: $expandGateway) {
                    GatewaySection(draft: $draft)
                } label: {
                    advancedLabel("gateway.advanced", systemImage: "arrow.triangle.branch",
                                  active: draft.jumpHost != nil || !draft.portForwardings.isEmpty || (draft.socks5Proxy?.enabled ?? false))
                }
            }
        }

        // 3. Serielle Parameter (Serial only)
        if draft.connectionType == .serial {
            Section {
                DisclosureGroup(isExpanded: $expandSerialParams) {
                    SerialParamControls(draft: $draft)
                } label: {
                    advancedLabel("session.adv.serial_params", systemImage: "slider.horizontal.3")
                }
            }
        }

        // 4. Terminal & Darstellung (all)
        Section {
            DisclosureGroup(isExpanded: $expandTerminal) {
                TerminalAppearanceControls(draft: $draft)
            } label: {
                advancedLabel("session.adv.terminal", systemImage: "paintpalette",
                              active: draft.themeId != nil || draft.terminalFontSize != nil || draft.highlightRuleset != nil)
            }
        }

        // 5. Verhalten (all)
        Section {
            DisclosureGroup(isExpanded: $expandBehaviour) {
                BehaviourControls(draft: $draft)
            } label: {
                advancedLabel("session.adv.behaviour", systemImage: "wand.and.stars",
                              active: draft.macroOnConnectId != nil || draft.autoConnectOnLaunch)
            }
        }
    }

    private func advancedLabel(_ key: LocalizedStringKey, systemImage: String, active: Bool = false) -> some View {
        HStack {
            Label(key, systemImage: systemImage)
            if active {
                Text("gateway.active_badge")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Bottom: name, folder, tags

    @ViewBuilder private var bottomSection: some View {
        Section {
            LabeledContent("session.name") {
                TextField("", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("session.description") {
                TextField("", text: $draft.description)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("session.folder") {
                FolderPicker(selectedId: $draft.folderId)
            }
        } header: {
            Text("session.organization")
        }
        Section {
            TagEditor(tags: $draft.tags)
        } header: {
            Text("session.tags")
        }
    }

    // MARK: - Helpers

    @ViewBuilder private func invalidBorder(when invalid: Bool) -> some View {
        if invalid {
            RoundedRectangle(cornerRadius: 5).stroke(Color.red.opacity(0.6), lineWidth: 1)
        }
    }

    /// Apply sensible per-protocol defaults when the user switches protocol.
    private func applyProtocolDefaults(_ newType: ConnectionType) {
        // Only adjust the port if it still equals another protocol's default
        // (don't clobber a custom port the user set).
        let knownDefaults = Set(ConnectionType.allCases.map(\.defaultPort))
        if knownDefaults.contains(draft.port) {
            draft.port = newType.defaultPort
        }
    }

    private func save() {
        // If quick-entry password was filled → auto-create Credential using draft.username
        if useQuickCredential && !quickPassword.isEmpty {
            var cred = Credential()
            cred.name = draft.name.isEmpty ? draft.host : draft.name
            cred.username = draft.username
            cred.password = quickPassword
            cred.isGroup = false    // session-specific, not shown in password group picker

            // Check if an identical credential already exists
            if let existing = vm.credentials.first(where: {
                $0.username == cred.username && $0.password == cred.password
            }) {
                draft.credentialId = existing.id
            } else {
                vm.addCredential(cred)
                draft.credentialId = cred.id
            }
        }

        if isEditing {
            vm.updateSession(draft)
        } else {
            vm.addSession(draft)
        }
        dismiss()
    }
}

// MARK: - Protocol icon bar (MobaXterm-style)

private struct ProtocolBar: View {
    @Binding var selected: ConnectionType
    let onChange: (ConnectionType) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(ConnectionType.allCases) { type in
                ProtocolButton(
                    type: type,
                    isSelected: selected == type,
                    isAvailable: type.isAvailable
                ) {
                    guard type.isAvailable else { return }
                    selected = type
                    onChange(type)
                }
            }
            Spacer()
        }
    }
}

private struct ProtocolButton: View {
    let type: ConnectionType
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    private var iconName: String {
        switch type {
        case .ssh:    return "terminal"
        case .telnet: return "network"
        case .serial: return "cable.connector"
        case .rdp:    return "display"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .medium))
                Text(type.rawValue)
                    .font(.caption.weight(.medium))
            }
            .frame(width: 78, height: 64)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isSelected ? 2 : 0.5)
            )
            .opacity(isAvailable ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .help(isAvailable ? Text(type.rawValue) : Text("session.protocol.coming_soon"))
    }

    private var foreground: Color {
        if !isAvailable { return .secondary }
        return isSelected ? .accentColor : .primary
    }
    private var background: Color {
        isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)
    }
}

// MARK: - Serial basic + parameter fields

private struct SerialBasicFields: View {
    @Binding var draft: Session
    @State private var availablePorts: [String] = []

    var body: some View {
        LabeledContent("session.serial.port") {
            Picker("", selection: $draft.serialPort) {
                Text("session.serial.port.select").tag("")
                ForEach(availablePorts, id: \.self) { Text($0).tag($0) }
                if !availablePorts.contains(draft.serialPort) && !draft.serialPort.isEmpty {
                    Text(draft.serialPort).tag(draft.serialPort)
                }
            }
            .labelsHidden()
            .onAppear { availablePorts = SerialService().availablePorts() }
        }
        LabeledContent("session.serial.baud") {
            Picker("", selection: $draft.serialBaudRate) {
                ForEach([300, 600, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400], id: \.self) {
                    Text("\($0)").tag($0)
                }
            }
            .labelsHidden()
        }
    }
}

private struct SerialParamControls: View {
    @Binding var draft: Session

    var body: some View {
        LabeledContent("session.serial.data_bits") {
            Picker("", selection: $draft.serialDataBits) {
                ForEach([5, 6, 7, 8], id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
        LabeledContent("session.serial.stop_bits") {
            Picker("", selection: $draft.serialStopBits) {
                Text("1").tag("1"); Text("2").tag("2")
            }
            .pickerStyle(.segmented).labelsHidden()
        }
        LabeledContent("session.serial.parity") {
            Picker("", selection: $draft.serialParity) {
                Text("serial.parity.none").tag("none")
                Text("serial.parity.even").tag("even")
                Text("serial.parity.odd").tag("odd")
            }
            .labelsHidden()
        }
        LabeledContent("session.serial.flow") {
            Picker("", selection: $draft.serialFlowControl) {
                Text("serial.flow.none").tag("none")
                Text("serial.flow.hardware").tag("hardware")
                Text("serial.flow.software").tag("software")
            }
            .labelsHidden()
        }
    }
}

// MARK: - SSH "Verbindung & Sicherheit" controls

private struct SecurityControls: View {
    @Binding var draft: Session

    var body: some View {
        Toggle("session.ssh.legacy", isOn: Binding(
            get: { draft.sshUseLegacyAlgorithms ?? false },
            set: { draft.sshUseLegacyAlgorithms = $0 }
        ))
        Toggle("session.ssh.strict_host_key", isOn: $draft.sshStrictHostKeyChecking)
        LabeledContent("session.ssh.timeout") {
            HStack {
                Stepper(value: $draft.connectTimeout, in: 1...120) {
                    Text("\(draft.connectTimeout) s")
                }
            }
        }
        Divider()
        LabeledContent("session.ssh.key") {
            HStack {
                TextField("session.ssh.key.placeholder", text: $draft.sshPrivateKeyPath)
                    .textFieldStyle(.roundedBorder)
                Button { selectKeyFile() } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain)
            }
        }
    }

    private func selectKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { result in
            if result == .OK, let url = panel.url { draft.sshPrivateKeyPath = url.path }
        }
    }
}

// MARK: - "Terminal & Darstellung" controls

private struct TerminalAppearanceControls: View {
    @Binding var draft: Session
    @State private var themeService = ThemeService.shared

    var body: some View {
        // Theme override (default = use global theme)
        LabeledContent("session.term.theme") {
            Picker("", selection: Binding(
                get: { draft.themeId },
                set: { draft.themeId = $0 }
            )) {
                Text("session.term.use_global").tag(Optional<UUID>.none)
                ForEach(themeService.themes) { theme in
                    Text(theme.name).tag(Optional(theme.id))
                }
            }
            .labelsHidden()
        }
        // Font size override
        LabeledContent("session.term.font_size") {
            HStack {
                Toggle("", isOn: Binding(
                    get: { draft.terminalFontSize != nil },
                    set: { draft.terminalFontSize = $0 ? 13 : nil }
                ))
                .labelsHidden()
                if let size = draft.terminalFontSize {
                    Stepper(value: Binding(
                        get: { size },
                        set: { draft.terminalFontSize = $0 }
                    ), in: 8...28, step: 1) {
                        Text("\(Int(size)) pt")
                    }
                } else {
                    Text("session.term.use_global").foregroundStyle(.secondary)
                }
            }
        }
        // Syntax highlighting ruleset override
        LabeledContent("session.term.highlight") {
            Picker("", selection: Binding(
                get: { draft.highlightRuleset ?? "__global__" },
                set: { draft.highlightRuleset = ($0 == "__global__") ? nil : $0 }
            )) {
                Text("session.term.use_global").tag("__global__")
                Text("syntax.ruleset.default").tag(HighlightRuleset.default.rawValue)
                Text("syntax.ruleset.cisco").tag(HighlightRuleset.ciscoIOS.rawValue)
                Text("syntax.ruleset.log").tag(HighlightRuleset.logLevel.rawValue)
                Text("syntax.ruleset.network").tag(HighlightRuleset.network.rawValue)
            }
            .labelsHidden()
        }
    }
}

// MARK: - "Verhalten" controls

private struct BehaviourControls: View {
    @Binding var draft: Session
    @State private var macroService = MacroService.shared

    var body: some View {
        LabeledContent("session.behaviour.macro") {
            Picker("", selection: Binding(
                get: { draft.macroOnConnectId },
                set: { draft.macroOnConnectId = $0 }
            )) {
                Text("session.behaviour.macro.none").tag(Optional<UUID>.none)
                ForEach(macroService.macros) { macro in
                    Text(macro.name.isEmpty ? String(localized: "macro.new") : macro.name)
                        .tag(Optional(macro.id))
                }
            }
            .labelsHidden()
        }
        Toggle("session.behaviour.autoconnect", isOn: $draft.autoConnectOnLaunch)
    }
}

// MARK: - Folder picker

struct FolderPicker: View {
    @Binding var selectedId: UUID?
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        Picker("", selection: $selectedId) {
            Text("session.folder.none").tag(Optional<UUID>.none)
            ForEach(vm.folders) { folder in
                Text(folderPath(folder)).tag(Optional(folder.id))
            }
        }
    }

    private func folderPath(_ folder: Folder) -> String {
        var parts = [folder.name]
        var parentId = folder.parentId
        while let pid = parentId {
            if let parent = vm.folders.first(where: { $0.id == pid }) {
                parts.insert(parent.name, at: 0)
                parentId = parent.parentId
            } else { break }
        }
        return parts.joined(separator: " / ")
    }
}

// MARK: - Password group picker (only shared groups, not session-specific credentials)

struct PasswordGroupPicker: View {
    @Binding var selectedId: UUID?
    @Environment(AppViewModel.self) private var vm

    private var groups: [Credential] { vm.credentials.filter { $0.isGroup } }

    var body: some View {
        Picker("session.pwgroup", selection: $selectedId) {
            Text("session.pwgroup.none").tag(Optional<UUID>.none)
            ForEach(groups) { cred in
                Text(cred.name.isEmpty ? cred.username : cred.name).tag(Optional(cred.id))
            }
        }
    }
}

// MARK: - Tag editor

struct TagEditor: View {
    @Binding var tags: [String]
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(label: tag) {
                        tags.removeAll { $0 == tag }
                    }
                }
            }
            HStack {
                TextField("tag.new", text: $newTag)
                    .onSubmit { addTag() }
                Button("action.add") { addTag() }
                    .disabled(newTag.isEmpty)
            }
        }
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty && !tags.contains(t) { tags.append(t) }
        newTag = ""
    }
}

struct TagChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(label).font(.caption)
            Button { onRemove() } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Flow layout helper

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
