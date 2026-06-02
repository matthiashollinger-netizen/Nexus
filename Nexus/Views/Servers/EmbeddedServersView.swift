import SwiftUI
import AppKit

// MARK: - Embedded Servers Window

struct EmbeddedServersView: View {
    @State private var serverService = EmbeddedServerService.shared
    @State private var showAddServer = false
    @State private var newServerType: EmbeddedServer.ServerType = .http
    @State private var configuringServer: EmbeddedServer? = nil
    @State private var errorMessage: String? = nil

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("servers.title")
                    .font(.headline)
                Spacer()
                Button {
                    showAddServer = true
                } label: {
                    Label("action.add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if serverService.servers.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("servers.empty")
                        .foregroundStyle(.secondary)
                    Button("action.add") { showAddServer = true }
                        .buttonStyle(.bordered)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach($serverService.servers) { $server in
                            ServerCard(server: $server,
                                       logs: serverService.logs(for: server),
                                       onStart: { Task { await startServer(server) } },
                                       onStop: { serverService.stop(server) },
                                       onConfigure: { configuringServer = server },
                                       onDelete: { deleteServer(server) })
                        }
                    }
                    .padding(16)
                }
            }

            if let err = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).font(.caption)
                    Spacer()
                    Button { errorMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }
        }
        .onAppear { serverService.loadServers() }
        .sheet(isPresented: $showAddServer) {
            AddServerSheet { type, port, root in
                addServer(type: type, port: port, rootDir: root)
            }
        }
        .sheet(item: $configuringServer) { server in
            if let idx = serverService.servers.firstIndex(where: { $0.id == server.id }) {
                ServerConfigSheet(server: $serverService.servers[idx]) {
                    configuringServer = nil
                    serverService.saveServers()
                }
            }
        }
    }

    private func addServer(type: EmbeddedServer.ServerType, port: Int, rootDir: String) {
        var server = EmbeddedServer(type: type, port: port)
        server.rootDirectory = rootDir
        serverService.servers.append(server)
        serverService.saveServers()
    }

    private func deleteServer(_ server: EmbeddedServer) {
        serverService.stop(server)
        serverService.servers.removeAll { $0.id == server.id }
        serverService.saveServers()
    }

    private func startServer(_ server: EmbeddedServer) async {
        do {
            try await serverService.start(server)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Server Card

struct ServerCard: View {
    @Binding var server: EmbeddedServer
    let logs: [String]
    let onStart: () -> Void
    let onStop: () -> Void
    let onConfigure: () -> Void
    let onDelete: () -> Void

    @State private var showLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: server.type.systemImage)
                    .font(.title2)
                    .foregroundStyle(server.isRunning ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.type.displayName)
                        .fontWeight(.semibold)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(server.isRunning ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(server.isRunning ? String(localized: "server.status.running") : String(localized: "server.status.stopped"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // Info
            HStack {
                Label(":\(server.port)", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if !server.rootDirectory.isEmpty {
                Text(server.rootDirectory)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()

            // TFTP port-69 root-privilege warning
            if server.type == .tftp && server.port == 69 {
                Label("server.tftp.root_warning", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Actions
            HStack(spacing: 8) {
                if server.isRunning {
                    Button("server.stop") { onStop() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                } else {
                    Button("server.start") { onStart() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                Button("server.configure") { onConfigure() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer()

                Button {
                    showLogs.toggle()
                } label: {
                    Image(systemName: showLogs ? "chevron.up" : "list.bullet.rectangle")
                }
                .buttonStyle(.borderless)
                .help("server.logs")

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            // Logs (expandable)
            if showLogs {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(logs.suffix(50), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if logs.isEmpty {
                            Text("–")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 80)
                .background(Color.black.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Add Server Sheet

struct AddServerSheet: View {
    let onAdd: (EmbeddedServer.ServerType, Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var type: EmbeddedServer.ServerType = .http
    @State private var port: Int = 8080
    @State private var rootDir = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("action.add")
                .font(.headline)

            Form {
                Picker("session.type", selection: $type) {
                    ForEach(EmbeddedServer.ServerType.allCases, id: \.self) { t in
                        if t.isAvailable {
                            Text(t.displayName).tag(t)
                        } else {
                            // Deactivated type shown but not selectable
                            Text("\(t.displayName) — \(String(localized: "server.coming_soon"))")
                                .tag(t)
                        }
                    }
                }
                .onChange(of: type) { _, new in
                    // Don't let the user land on a deactivated type.
                    if !new.isAvailable { type = .http }
                    port = type.defaultPort
                }

                if !type.isAvailable {
                    Label("server.ftp_unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                LabeledContent("server.port") {
                    TextField("server.port", value: $port, format: .number)
                        .frame(width: 80)
                }

                LabeledContent("server.root") {
                    HStack {
                        Text(rootDir.isEmpty ? "~/" : rootDir)
                            .foregroundStyle(rootDir.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("action.edit") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            if panel.runModal() == .OK {
                                rootDir = panel.url?.path ?? ""
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("action.cancel", role: .cancel) { dismiss() }
                Button("action.add") {
                    onAdd(type, port, rootDir)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

// MARK: - Server Config Sheet

struct ServerConfigSheet: View {
    @Binding var server: EmbeddedServer
    let onDone: () -> Void

    @State private var rootDir: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("server.configure")
                .font(.headline)

            Form {
                LabeledContent("server.port") {
                    TextField("", value: $server.port, format: .number)
                        .frame(width: 80)
                }

                LabeledContent("server.root") {
                    HStack {
                        Text(server.rootDirectory.isEmpty ? "~/" : server.rootDirectory)
                            .foregroundStyle(server.rootDirectory.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Button("action.edit") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            if panel.runModal() == .OK {
                                server.rootDirectory = panel.url?.path ?? ""
                            }
                        }
                        .controlSize(.small)
                    }
                }

                Toggle("server.autostart", isOn: $server.autoStart)
            }
            .formStyle(.grouped)

            Button("action.save") { onDone() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 380)
    }
}
