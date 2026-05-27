import SwiftUI

struct AddSessionView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    var existingSession: Session?
    var parentFolderId: UUID?

    @State private var draft: Session
    // Quick-entry credential — username comes from draft.username (Network section)
    @State private var quickPassword: String = ""
    @State private var useQuickCredential: Bool = false

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
    // Existing linked credential name (for display)
    private var linkedCredentialName: String? {
        guard let cid = draft.credentialId else { return nil }
        let cred = vm.credentials.first { $0.id == cid }
        return cred?.name.isEmpty == false ? cred?.name : cred?.username
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("session.general") {
                    LabeledContent("session.name") {
                        TextField("session.name.placeholder", text: $draft.name)
                    }
                    LabeledContent("session.type") {
                        Picker("", selection: $draft.connectionType) {
                            ForEach(ConnectionType.allCases) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    LabeledContent("session.folder") {
                        FolderPicker(selectedId: $draft.folderId)
                    }
                }

                if draft.connectionType == .serial {
                    SerialSection(draft: $draft)
                } else {
                    NetworkSection(draft: $draft)
                }

                if draft.connectionType == .ssh {
                    SSHSection(draft: $draft)
                }

                // ── Zugangsdaten ──────────────────────────────────────
                Section {
                    // If already linked to a credential
                    if let credName = linkedCredentialName {
                        HStack {
                            Image(systemName: "key.fill").foregroundStyle(.secondary)
                            Text(credName)
                            Spacer()
                            Button("action.change") { draft.credentialId = nil }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                                .font(.callout)
                        }
                    } else {
                        // Choose existing credential
                        CredentialPicker(selectedId: $draft.credentialId)
                            .onChange(of: draft.credentialId) { _, newVal in
                                if newVal != nil { useQuickCredential = false }
                            }

                        Divider()

                        // OR enter credentials inline
                        Toggle("session.credential.enter_now", isOn: $useQuickCredential)
                            .onChange(of: useQuickCredential) { _, on in
                                if on { draft.credentialId = nil }
                            }

                        if useQuickCredential {
                            LabeledContent("cred.password") {
                                SecureField("cred.password.placeholder", text: $quickPassword)
                            }
                        }
                    }
                } header: {
                    Text("session.credential")
                } footer: {
                    if useQuickCredential && !quickPassword.isEmpty {
                        Label("session.credential.auto_save_hint", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("session.tags") {
                    TagEditor(tags: $draft.tags)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .disabled(draft.host.isEmpty && draft.connectionType != .serial)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    private func save() {
        // If quick-entry password was filled → auto-create Credential using draft.username
        if useQuickCredential && !quickPassword.isEmpty {
            var cred = Credential()
            cred.name = draft.name.isEmpty ? draft.host : draft.name
            cred.username = draft.username
            cred.password = quickPassword

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

// MARK: - Sub-sections

struct NetworkSection: View {
    @Binding var draft: Session

    var body: some View {
        Section("session.network") {
            LabeledContent("session.host") {
                TextField("session.host.placeholder", text: $draft.host)
                    .autocorrectionDisabled()
            }
            LabeledContent("session.port") {
                TextField("", value: $draft.port, format: .number)
                    .frame(width: 80)
            }
            LabeledContent("session.username") {
                TextField("session.username.placeholder", text: $draft.username)
                    .autocorrectionDisabled()
            }
        }
    }
}

struct SSHSection: View {
    @Binding var draft: Session

    var body: some View {
        Section("session.ssh") {
            LabeledContent("session.ssh.key") {
                HStack {
                    TextField("session.ssh.key.placeholder", text: $draft.sshPrivateKeyPath)
                    Button {
                        selectKeyFile()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                }
            }
            Toggle("session.ssh.legacy", isOn: Binding(
                get: { draft.sshUseLegacyAlgorithms ?? false },
                set: { draft.sshUseLegacyAlgorithms = $0 }
            ))
            Toggle("session.ssh.strict_host_key", isOn: $draft.sshStrictHostKeyChecking)
        }
    }

    private func selectKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { result in
            if result == .OK, let url = panel.url {
                draft.sshPrivateKeyPath = url.path
            }
        }
    }
}

struct SerialSection: View {
    @Binding var draft: Session
    @State private var availablePorts: [String] = []

    var body: some View {
        Section("session.serial") {
            LabeledContent("session.serial.port") {
                Picker("", selection: $draft.serialPort) {
                    Text("session.serial.port.select").tag("")   // placeholder tag matches empty default
                    ForEach(availablePorts, id: \.self) { Text($0).tag($0) }
                    if !availablePorts.contains(draft.serialPort) && !draft.serialPort.isEmpty {
                        Text(draft.serialPort).tag(draft.serialPort)
                    }
                }
                .onAppear {
                    availablePorts = SerialService().availablePorts()
                }
            }
            LabeledContent("session.serial.baud") {
                Picker("", selection: $draft.serialBaudRate) {
                    ForEach([300, 600, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400], id: \.self) {
                        Text("\($0)").tag($0)
                    }
                }
            }
            LabeledContent("session.serial.data_bits") {
                Picker("", selection: $draft.serialDataBits) {
                    ForEach([5, 6, 7, 8], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            LabeledContent("session.serial.stop_bits") {
                Picker("", selection: $draft.serialStopBits) {
                    Text("1").tag("1")
                    Text("2").tag("2")
                }
                .pickerStyle(.segmented)
            }
            LabeledContent("session.serial.parity") {
                Picker("", selection: $draft.serialParity) {
                    Text("serial.parity.none").tag("none")
                    Text("serial.parity.even").tag("even")
                    Text("serial.parity.odd").tag("odd")
                }
            }
            LabeledContent("session.serial.flow") {
                Picker("", selection: $draft.serialFlowControl) {
                    Text("serial.flow.none").tag("none")
                    Text("serial.flow.hardware").tag("hardware")
                    Text("serial.flow.software").tag("software")
                }
            }
        }
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

// MARK: - Credential picker

struct CredentialPicker: View {
    @Binding var selectedId: UUID?
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        Picker("session.credential", selection: $selectedId) {
            Text("session.credential.none").tag(Optional<UUID>.none)
            ForEach(vm.credentials) { cred in
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
