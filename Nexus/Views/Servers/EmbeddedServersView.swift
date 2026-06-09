import SwiftUI
import AppKit

// MARK: - Embedded Servers Window

struct EmbeddedServersView: View {
    @State private var serverService = EmbeddedServerService.shared
    @State private var configuringServer: EmbeddedServer? = nil
    @State private var errorMessage: String? = nil

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "server.rack").foregroundStyle(.secondary)
                Text("servers.title").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(EmbeddedServer.ServerType.allCases) { type in
                        cardForType(type)
                    }
                }
                .padding(16)
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
        .frame(minWidth: 560, minHeight: 460)
        .onAppear {
            serverService.loadServers()
            ensureDefaultInstances()
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

    // MARK: - One card per server type

    @ViewBuilder
    private func cardForType(_ type: EmbeddedServer.ServerType) -> some View {
        if type.isAvailable, let idx = serverService.servers.firstIndex(where: { $0.type == type }) {
            ServerCard(server: $serverService.servers[idx],
                       logs: serverService.logs(for: serverService.servers[idx]),
                       onStart: { Task { await startServer(serverService.servers[idx]) } },
                       onStop: { serverService.stop(serverService.servers[idx]) },
                       onConfigure: { configuringServer = serverService.servers[idx] })
        } else {
            DeactivatedServerCard(type: type)
        }
    }

    /// Ensures a persisted instance exists for each startable server type.
    private func ensureDefaultInstances() {
        var changed = false
        for type in EmbeddedServer.ServerType.allCases where type.isAvailable {
            if !serverService.servers.contains(where: { $0.type == type }) {
                serverService.servers.append(EmbeddedServer(type: type, port: type.defaultPort))
                changed = true
            }
        }
        if changed { serverService.saveServers() }
    }

    private func startServer(_ server: EmbeddedServer) async {
        do {
            try await serverService.start(server)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Deactivated server card (SFTP, Telnet)

private struct DeactivatedServerCard: View {
    let type: EmbeddedServer.ServerType

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: type.systemImage).font(.title2).foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName).fontWeight(.semibold).foregroundStyle(.secondary)
                    Text("server.coming_soon").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            Text(LocalizedStringKey(type.noteKey))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .opacity(0.7)
    }
}

// MARK: - Server Card

struct ServerCard: View {
    @Binding var server: EmbeddedServer
    let logs: [String]
    let onStart: () -> Void
    let onStop: () -> Void
    let onConfigure: () -> Void

    @State private var showLogs = false

    /// The address a client/switch should use, e.g. "tftp://192.168.90.10:6969".
    private var reachableAddress: String {
        let ip = EmbeddedServerService.localIPAddress() ?? "127.0.0.1"
        let scheme: String
        switch server.type {
        case .http:   scheme = "http"
        case .tftp:   scheme = "tftp"
        case .ftp:    scheme = "ftp"
        case .sftp:   scheme = "sftp"
        case .telnet: scheme = "telnet"
        }
        return "\(scheme)://\(ip):\(server.port)"
    }

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

            // Reachable address (what to type on the switch) — shown while running.
            if server.isRunning {
                Label(reachableAddress, systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption.monospaced())
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if !server.rootDirectory.isEmpty {
                Text(server.rootDirectory)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()

            // Privileged-port warning (ports < 1024 need root)
            if server.port < 1024 {
                Label("server.privileged_port_warning", systemImage: "exclamationmark.triangle.fill")
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
