import SwiftUI
import UniformTypeIdentifiers

// MARK: - Target field for column mapping

enum CSVTargetField: CaseIterable, Identifiable, Hashable {
    case skip, name, host, proto, port, username, password, folder, tags, description

    var id: Self { self }

    var labelKey: LocalizedStringKey {
        switch self {
        case .skip:        return "import.field.skip"
        case .name:        return "import.field.name"
        case .host:        return "import.field.host"
        case .proto:       return "import.field.proto"
        case .port:        return "import.field.port"
        case .username:    return "import.field.username"
        case .password:    return "import.field.password"
        case .folder:      return "import.field.folder"
        case .tags:        return "import.field.tags"
        case .description: return "import.field.description"
        }
    }
}

// MARK: - Main View

struct ImportCSVView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    @State private var headers: [String] = []
    @State private var rows: [[String]] = []
    @State private var mapping: [CSVTargetField] = []

    @State private var showFilePicker = false
    @State private var importedCount: Int? = nil

    // MARK: Preview (first data row with current mapping)
    var previewSession: CSVPreviewData? {
        guard let firstRow = rows.first, !mapping.isEmpty else { return nil }
        var d = CSVPreviewData()
        for (i, target) in mapping.enumerated() {
            let val = firstRow[safeIdx: i] ?? ""
            guard !val.isEmpty else { continue }
            switch target {
            case .name:        d.name        = val
            case .host:        d.host        = val
            case .proto:       d.proto       = val.lowercased()
            case .port:        d.port        = val
            case .username:    d.username    = val
            case .password:    d.password    = val
            case .folder:      d.folder      = val
            case .tags:        d.tags        = val
            case .description: d.description = val
            case .skip:        break
            }
        }
        if d.name.isEmpty { d.name = d.host }
        if d.proto.isEmpty { d.proto = "ssh" }
        return d.host.isEmpty ? nil : d
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── File picker ──────────────────────────────────────
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label(headers.isEmpty ? "import.choose_file" : "import.choose_file_again",
                              systemImage: "doc.badge.plus")
                    }
                    if !rows.isEmpty {
                        Text(String(format: String(localized: "import.rows_loaded"), rows.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // ── Column mapping ───────────────────────────────────
                if !headers.isEmpty {
                    Section {
                        ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                            LabeledContent(header) {
                                Picker("", selection: $mapping[idx]) {
                                    ForEach(CSVTargetField.allCases) { field in
                                        Text(field.labelKey).tag(field)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 180)
                            }
                        }
                    } header: {
                        Text("import.mapping.title")
                    }

                    // ── Preview ──────────────────────────────────────
                    if let p = previewSession {
                        Section("import.preview.title") {
                            CSVPreviewRow(data: p)
                        }
                    }
                }

                // ── Result ───────────────────────────────────────────
                if let count = importedCount {
                    Section {
                        Label(String(format: String(localized: "import.success"), count),
                              systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("import.csv.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.import") { doImport() }
                        .disabled(headers.isEmpty || importedCount != nil)
                }
            }
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard let url = try? result.get() else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                parseCSV(content)
            }
        }
        .frame(minWidth: 540, minHeight: 480)
    }

    // MARK: - Parse

    private func parseCSV(_ content: String) {
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let headerLine = lines.first else { return }

        headers = parseCSVLine(headerLine)
        rows = lines.dropFirst().map { parseCSVLine($0) }
        importedCount = nil

        // Auto-detect mapping from header names
        mapping = headers.map { header in
            let h = header.lowercased()
            if h.contains("label") || h == "name" { return .name }
            if h.contains("host") || h.contains("ip") || h.contains("addr") { return .host }
            if h.contains("proto") || h.contains("type") { return .proto }
            if h.contains("port") { return .port }
            if h.contains("user") { return .username }
            if h.contains("pass") { return .password }
            if h.contains("group") || h.contains("folder") || h.contains("categor") { return .folder }
            if h.contains("tag") { return .tags }
            if h.contains("desc") || h.contains("note") || h.contains("comment") { return .description }
            return .skip
        }
    }

    // MARK: - Import

    private func doImport() {
        var newFolders: [Folder] = []
        var folderCache: [String: UUID] = [:]
        var newSessions: [Session] = []
        var newCredentials: [Credential] = []

        for row in rows {
            // Build field map
            var fields: [CSVTargetField: String] = [:]
            for (i, target) in mapping.enumerated() {
                let val = row[safeIdx: i] ?? ""
                if target != .skip && !val.isEmpty {
                    fields[target] = val
                }
            }

            let host = fields[.host] ?? ""
            guard !host.isEmpty else { continue }

            let proto = (fields[.proto] ?? "ssh").lowercased()
            let connType: ConnectionType = {
                switch proto {
                case "telnet": return .telnet
                case "serial": return .serial
                default:       return .ssh
                }
            }()

            // Folder resolution
            var folderId: UUID? = nil
            if let folderName = fields[.folder] {
                if let existing = vm.folders.first(where: { $0.name == folderName && $0.parentId == nil }) {
                    folderId = existing.id
                } else if let cached = folderCache[folderName] {
                    folderId = cached
                } else {
                    var f = Folder()
                    f.name = folderName
                    newFolders.append(f)
                    folderCache[folderName] = f.id
                    folderId = f.id
                }
            }

            // Session
            var s = Session()
            s.name = fields[.name] ?? host
            s.host = host
            s.port = Int(fields[.port] ?? "") ?? connType.defaultPort
            s.username = fields[.username] ?? ""
            s.description = fields[.description] ?? ""
            s.connectionType = connType
            s.folderId = folderId
            if let tagsStr = fields[.tags] {
                s.tags = tagsStr
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }

            // Credential (if username or password present)
            let username = fields[.username] ?? ""
            let password = fields[.password] ?? ""
            if !username.isEmpty || !password.isEmpty {
                let allCreds = vm.credentials + newCredentials
                if let existing = allCreds.first(where: {
                    $0.username == username && $0.password == password
                }) {
                    s.credentialId = existing.id
                } else {
                    var cred = Credential()
                    cred.name = s.name
                    cred.username = username
                    cred.password = password
                    newCredentials.append(cred)
                    s.credentialId = cred.id
                }
            }

            newSessions.append(s)
        }

        vm.addImportedData(sessions: newSessions, folders: newFolders, credentials: newCredentials)
        importedCount = newSessions.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
    }

    // MARK: - CSV line parser

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" { inQuotes.toggle() }
            else if ch == "," && !inQuotes { fields.append(current); current = "" }
            else { current.append(ch) }
        }
        fields.append(current)
        return fields
    }
}

// MARK: - Preview card

struct CSVPreviewData {
    var name = "", host = "", proto = "ssh", port = ""
    var username = "", password = "", folder = "", tags = "", description = ""
}

struct CSVPreviewRow: View {
    let data: CSVPreviewData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: protoIcon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.name.isEmpty ? data.host : data.name)
                        .fontWeight(.medium)
                    HStack(spacing: 4) {
                        Text(data.host)
                        if !data.port.isEmpty {
                            Text(":\(data.port)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if !data.username.isEmpty || !data.folder.isEmpty || !data.tags.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    if !data.username.isEmpty {
                        Label(data.username, systemImage: "person")
                    }
                    if !data.description.isEmpty {
                        Label(data.description, systemImage: "text.alignleft")
                    }
                    if !data.folder.isEmpty {
                        Label(data.folder, systemImage: "folder")
                    }
                    if !data.tags.isEmpty {
                        Label(data.tags, systemImage: "tag")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    var protoIcon: String {
        switch data.proto {
        case "telnet": return "network"
        case "serial": return "cable.connector"
        default:       return "terminal"
        }
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safeIdx index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
