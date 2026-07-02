import SwiftUI
import UniformTypeIdentifiers

struct PasswordManagerView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showAddCredential = false
    @State private var editingCredential: Credential? = nil
    @State private var showExport = false
    @State private var showImport = false
    @State private var exportError: String? = nil

    var filteredGroups: [Credential] {
        let all = vm.credentials.filter { $0.isGroup }
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredSessionCreds: [Credential] {
        let all = vm.credentials.filter { !$0.isGroup }
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $editingCredential) {
                // Password groups (shared, reusable)
                if !filteredGroups.isEmpty || searchText.isEmpty {
                    Section("pwmgr.groups") {
                        ForEach(filteredGroups) { cred in
                            CredentialRowView(credential: cred).tag(cred)
                        }
                    }
                }
                // Session-specific credentials (auto-created, not reusable via picker)
                if !filteredSessionCreds.isEmpty {
                    Section("pwmgr.session_creds") {
                        ForEach(filteredSessionCreds) { cred in
                            CredentialRowView(credential: cred).tag(cred)
                        }
                    }
                }
            }
            .searchable(text: $searchText)
            .listStyle(.sidebar)
            .navigationTitle("pwmgr.title")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button { showAddCredential = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button { showExport = true } label: {
                            Label("pwmgr.export", systemImage: "square.and.arrow.up")
                        }
                        Button { showImport = true } label: {
                            Label("pwmgr.import", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        } detail: {
            if let cred = editingCredential {
                CredentialDetailView(credential: cred)
            } else {
                ContentUnavailableView("pwmgr.select", systemImage: "key")
            }
        }
        .sheet(isPresented: $showAddCredential) {
            CredentialEditSheet(credential: nil)
        }
        .fileExporter(
            isPresented: $showExport,
            document: NexusExportDocument(vm: vm),
            contentType: .json,
            defaultFilename: "nexus-export"
        ) { _ in }
        .frame(minWidth: 700, minHeight: 460)
    }
}

// MARK: - Credential row

struct CredentialRowView: View {
    let credential: Credential

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(credential.name.isEmpty ? credential.username : credential.name)
                .fontWeight(.medium)
            Text(credential.username)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Credential detail

struct CredentialDetailView: View {
    let credential: Credential
    @Environment(AppViewModel.self) private var vm
    @State private var showEdit = false
    @State private var revealPassword = false
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            Section("pwmgr.info") {
                LabeledContent("cred.name") { Text(credential.name) }
                LabeledContent("cred.username") { Text(credential.username) }
                LabeledContent("cred.password") {
                    HStack {
                        if revealPassword {
                            Text(credential.password)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            Text(String(repeating: "•", count: credential.password.count))
                        }
                        Button {
                            revealPassword.toggle()
                        } label: {
                            Image(systemName: revealPassword ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(credential.password, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !credential.privateKey.isEmpty {
                    LabeledContent("cred.private_key") {
                        Text("cred.private_key.set")
                            .foregroundStyle(.secondary)
                    }
                }
                if !credential.notes.isEmpty {
                    LabeledContent("cred.notes") { Text(credential.notes) }
                }
            }
            Section {
                LabeledContent("cred.updated") {
                    Text(credential.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog(
            Text(String(format: NSLocalizedString("cred.delete.confirm", comment: ""), credential.name)),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("action.delete", role: .destructive) { vm.deleteCredential(credential) }
            Button("action.cancel", role: .cancel) { }
        } message: {
            Text("cred.delete.confirm.message")
        }
        .sheet(isPresented: $showEdit) {
            CredentialEditSheet(credential: credential)
        }
    }
}

// MARK: - Credential edit sheet

struct CredentialEditSheet: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    var existingCredential: Credential?
    @State private var draft: Credential

    init(credential: Credential?) {
        self.existingCredential = credential
        _draft = State(initialValue: credential ?? Credential())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("cred.info") {
                    LabeledContent("cred.name") {
                        TextField("", text: $draft.name)
                    }
                    LabeledContent("cred.username") {
                        TextField("", text: $draft.username)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("cred.password") {
                        SecureField("", text: $draft.password)
                    }
                }
                Section("cred.private_key") {
                    TextEditor(text: $draft.privateKey)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 100)
                    LabeledContent("cred.passphrase") {
                        SecureField("", text: $draft.privateKeyPassphrase)
                    }
                }
                Section("cred.notes") {
                    TextEditor(text: $draft.notes)
                        .frame(height: 80)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingCredential == nil ? String(localized: "cred.new") : String(localized: "cred.edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 480)
    }

    private func save() {
        if existingCredential != nil {
            vm.updateCredential(draft)
        } else {
            vm.addCredential(draft)
        }
        dismiss()
    }
}

// MARK: - Export document (plain JSON, no custom UTType needed)
// Note: NexusExport.Encodable is @MainActor-isolated (project default). This is a warning
// in targeted concurrency mode; fileWrapper is always called on the main thread by SwiftUI.

struct NexusExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let vm: AppViewModel

    init(vm: AppViewModel) { self.vm = vm }
    init(configuration: ReadConfiguration) throws { vm = AppViewModel() }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let bundle = NexusExport(
            sessions: vm.sessions,
            folders: vm.folders,
            credentials: vm.credentials,
            settings: vm.settings,
            exportDate: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(bundle)
        return FileWrapper(regularFileWithContents: data)
    }
}
