import SwiftUI
import AppKit

// MARK: - Embedded Servers Window  (DS v3.0)

struct EmbeddedServersView: View {
    @State private var serverService = EmbeddedServerService.shared
    @State private var configuringServer: EmbeddedServer? = nil
    @State private var errorMessage: String? = nil

    private let columns = [GridItem(.flexible(), spacing: DS.Space.md), GridItem(.flexible(), spacing: DS.Space.md)]

    /// The server types offered in the manager. Syslog/Telnet are intentionally
    /// hidden (not needed); SMB is surfaced via macOS File Sharing (see SMBCard).
    static let shownTypes: [EmbeddedServer.ServerType] = [.http, .tftp, .ftp]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                IconBadge(systemImage: "server.rack", pointSize: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("servers.title").font(DS.Font.title)
                    Text("servers.subtitle").font(DS.Font.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(DS.Space.xl)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: DS.Space.md) {
                    ForEach(Self.shownTypes) { type in
                        cardForType(type)
                    }
                    SMBCard()
                }
                .padding(DS.Space.xl)
            }

            if let err = errorMessage {
                HStack {
                    InfoCard(style: .danger, message: LocalizedStringKey(err))
                    Button { errorMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(DS.Space.md)
            }
        }
        .frame(minWidth: 620, minHeight: 500)
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

    @ViewBuilder
    private func cardForType(_ type: EmbeddedServer.ServerType) -> some View {
        // All shown types are available; the instance is created by ensureDefaultInstances.
        if let idx = serverService.servers.firstIndex(where: { $0.type == type }) {
            ServerCard(server: $serverService.servers[idx],
                       logs: serverService.logs(for: serverService.servers[idx]),
                       syslogServer: nil,
                       onStart: { Task { await startServer(serverService.servers[idx]) } },
                       onStop: { serverService.stop(serverService.servers[idx]) },
                       onConfigure: { configuringServer = serverService.servers[idx] })
        }
    }

    private func ensureDefaultInstances() {
        var changed = false
        for type in Self.shownTypes {
            if !serverService.servers.contains(where: { $0.type == type }) {
                serverService.servers.append(EmbeddedServer(type: type, port: type.defaultPort))
                changed = true
            }
        }
        if changed { serverService.saveServers() }
    }

    private func startServer(_ server: EmbeddedServer) async {
        do { try await serverService.start(server) }
        catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - SMB card (macOS File Sharing)
//
// A full SMB server can't be shipped in-process (huge protocol), but macOS already
// has one. Surface it like a server and jump straight to the Sharing settings.

private struct SMBCard: View {
    var body: some View {
        NexusCard(hoverLift: false) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.title3).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(DS.Color.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SMB").font(DS.Font.headline)
                        Text("server.system_service").font(DS.Font.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text("server.note.smb")
                    .font(DS.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("server.open_settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }
}

// MARK: - Server Card

struct ServerCard: View {
    @Binding var server: EmbeddedServer
    let logs: [String]
    var syslogServer: NativeSyslogServer? = nil
    let onStart: () -> Void
    let onStop: () -> Void
    let onConfigure: () -> Void

    @State private var showLogs = false

    private var state: ConnectionState { server.isRunning ? .connected : .idle }

    private var reachableAddress: String {
        let ip = EmbeddedServerService.localIPAddress() ?? "127.0.0.1"
        let scheme: String
        switch server.type {
        case .http:   scheme = "http"
        case .tftp:   scheme = "tftp"
        case .ftp:    scheme = "ftp"
        case .syslog: scheme = "udp"
        case .sftp:   scheme = "sftp"
        case .telnet: scheme = "telnet"
        }
        return "\(scheme)://\(ip):\(server.port)"
    }

    private var rootURL: URL {
        URL(fileURLWithPath: server.rootDirectory.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path : server.rootDirectory)
    }

    var body: some View {
        NexusCard(hoverLift: false) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                header
                info
                if server.isRunning {
                    Label(reachableAddress, systemImage: "antenna.radiowaves.left.and.right")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.stateConnected)
                        .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
                if server.type.usesRootDirectory && !server.rootDirectory.isEmpty {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([rootURL]) } label: {
                        Label(server.rootDirectory, systemImage: "folder")
                            .font(DS.Font.caption).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.plain).help("server.open_in_finder")
                }

                Divider()

                if server.port < 1024 {
                    Label("server.privileged_port_warning", systemImage: "exclamationmark.triangle.fill")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.stateConnecting)
                }

                actions

                if showLogs { logSection }
            }
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: server.type.systemImage)
                .font(.title3).symbolRenderingMode(.hierarchical)
                .foregroundStyle(server.isRunning ? DS.Color.accent : .secondary)
            Text(server.type.displayName).font(DS.Font.headline)
            Spacer()
            StateBadge(state: state)
        }
    }

    private var info: some View {
        HStack {
            // Text(verbatim:) avoids the LocalizedStringKey number grouping that turned
            // 8080 into "8.080" in German.
            Label { Text(verbatim: ":\(server.port)") } icon: { Image(systemName: "number") }
                .font(DS.Font.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var actions: some View {
        HStack(spacing: DS.Space.sm) {
            if server.isRunning {
                Button("server.stop") { onStop() }
                    .buttonStyle(.bordered).controlSize(.small).tint(.red)
            } else {
                Button("server.start") { onStart() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            Button("server.configure") { onConfigure() }
                .buttonStyle(.bordered).controlSize(.small)
            Spacer()
            Button { showLogs.toggle() } label: {
                Image(systemName: showLogs ? "chevron.up" : "list.bullet.rectangle")
            }
            .buttonStyle(.borderless).help("server.logs")
        }
    }

    @ViewBuilder private var logSection: some View {
        if server.type == .syslog, let syslog = syslogServer {
            SyslogLogView(server: syslog)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.hairline, lineWidth: 0.5))
        } else if server.type == .syslog {
            Text("syslog.start_to_view").font(DS.Font.caption).foregroundStyle(.secondary)
                .padding(.vertical, DS.Space.sm)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if logs.isEmpty {
                        MonoText("–")
                    } else {
                        ForEach(logs.suffix(50), id: \.self) { line in
                            MonoText(line).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(DS.Space.sm)
            }
            .frame(height: 90)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.hairline, lineWidth: 0.5))
        }
    }
}

// MARK: - Server Config Sheet

struct ServerConfigSheet: View {
    @Binding var server: EmbeddedServer
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.md) {
                IconBadge(systemImage: server.type.systemImage, pointSize: 18)
                Text(server.type.displayName).font(DS.Font.title)
                Spacer()
            }

            Form {
                LabeledContent("server.port") {
                    // .grouping(.never) → "8080", not "8.080" (German thousands separator).
                    TextField("", value: $server.port, format: .number.grouping(.never)).frame(width: 80)
                }
                if server.type.usesRootDirectory {
                    LabeledContent("server.root") {
                        HStack {
                            Text(server.rootDirectory.isEmpty ? "~/" : server.rootDirectory)
                                .foregroundStyle(server.rootDirectory.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                            Button("action.edit") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                if panel.runModal() == .OK { server.rootDirectory = panel.url?.path ?? "" }
                            }
                            .controlSize(.small)
                        }
                    }
                }
                if server.type == .ftp {
                    Section {
                        LabeledContent("server.ftp.user") {
                            TextField("server.ftp.anonymous", text: $server.ftpUsername).frame(width: 160)
                        }
                        LabeledContent("server.ftp.password") {
                            SecureField("", text: $server.ftpPassword).frame(width: 160)
                        }
                    } header: {
                        Text("server.ftp.auth")
                    } footer: {
                        Text("server.ftp.auth.hint").font(DS.Font.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("server.autostart", isOn: $server.autoStart)
            }
            .formStyle(.grouped)

            Button("action.save") { onDone() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(DS.Space.xxl)
        .frame(width: 420)
    }
}
