import SwiftUI
import AppKit

// MARK: - SFTP Browser View

struct SFTPBrowserView: View {
    @Environment(AppViewModel.self) private var vm
    let cs: ConnectionSession

    @State private var items: [SFTPItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showHiddenFiles = false
    @State private var transferProgress: TransferProgress? = nil
    @State private var renameItem: SFTPItem? = nil
    @State private var renameText = ""
    @State private var showNewFolderDialog = false
    @State private var newFolderName = ""

    private var currentPath: String {
        vm.sftpCurrentPath
    }

    private var displayedItems: [SFTPItem] {
        showHiddenFiles ? items : items.filter { !$0.name.hasPrefix(".") }
    }

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            // Breadcrumb navigation
            BreadcrumbView(path: currentPath) { path in
                vm.sftpCurrentPath = path
                Task { await loadDirectory(path: path) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // File list
            if isLoading {
                Spacer()
                ProgressView()
                    .padding()
                Spacer()
            } else if let err = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("sftp.retry") {
                        Task { await loadDirectory(path: currentPath) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Spacer()
            } else {
                List(displayedItems) { item in
                    SFTPItemRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if item.isDirectory {
                                let newPath = item.path.hasSuffix("/") ? item.path : item.path + "/"
                                vm.sftpCurrentPath = newPath
                                Task { await loadDirectory(path: newPath) }
                            } else {
                                Task { await downloadAndOpen(item: item) }
                            }
                        }
                        .contextMenu {
                            SFTPContextMenu(item: item,
                                           onDownload: { Task { await downloadFile(item: item) } },
                                           onRename: { renameItem = item; renameText = item.name },
                                           onDelete: { Task { await deleteItem(item: item) } },
                                           onNewFolder: { showNewFolderDialog = true })
                        }
                }
                .listStyle(.plain)
            }

            Divider()

            // Toolbar
            HStack(spacing: 6) {
                Button {
                    Task { await loadDirectory(path: currentPath) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("sftp.refresh")

                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("sftp.upload")

                Button {
                    showNewFolderDialog = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .help("sftp.new_folder")

                Spacer()

                Button {
                    showHiddenFiles.toggle()
                } label: {
                    Image(systemName: showHiddenFiles ? "eye.fill" : "eye.slash")
                }
                .buttonStyle(.plain)
                .help("sftp.toggle_hidden")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 280)
        .onAppear {
            Task { await loadDirectory(path: currentPath) }
        }
        // Reset path + reload when the connected session changes
        // (e.g. user switches to a different SSH tab while SFTP panel is open)
        .onChange(of: cs.id) { _, _ in
            vm.sftpCurrentPath = "/"
            items = []
            Task { await loadDirectory(path: "/") }
        }
        // Transfer progress overlay
        .overlay {
            if let progress = transferProgress {
                TransferProgressOverlay(progress: progress)
            }
        }
        // Rename sheet
        .sheet(item: $renameItem) { item in
            RenameSheet(name: $renameText) {
                Task { await renameItem(item, to: renameText) }
                renameItem = nil
            } onCancel: {
                renameItem = nil
            }
        }
        // New folder alert
        .alert("sftp.new_folder", isPresented: $showNewFolderDialog) {
            TextField("sftp.folder_name", text: $newFolderName)
            Button("action.cancel", role: .cancel) { newFolderName = "" }
            Button("action.add") {
                let name = newFolderName
                newFolderName = ""
                Task { await createFolder(name: name) }
            }
        }
    }

    // MARK: - Actions

    private func loadDirectory(path: String) async {
        guard let sshInfo = sshConnectionInfo() else { return }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await SFTPService.shared.listDirectory(
                host: sshInfo.host, port: sshInfo.port,
                username: sshInfo.username, password: sshInfo.password,
                keyPath: sshInfo.keyPath, path: path)
            items = result.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func downloadFile(item: SFTPItem) async {
        guard let sshInfo = sshConnectionInfo() else { return }
        transferProgress = TransferProgress(filename: item.name, type: .download, fraction: 0)

        let destURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent(item.name)

        do {
            try await SFTPService.shared.downloadFile(
                host: sshInfo.host, port: sshInfo.port,
                username: sshInfo.username, password: sshInfo.password,
                keyPath: sshInfo.keyPath, remotePath: item.path, to: destURL)
            transferProgress = nil
            NSWorkspace.shared.selectFile(destURL.path, inFileViewerRootedAtPath: destURL.deletingLastPathComponent().path)
        } catch {
            transferProgress = nil
            errorMessage = error.localizedDescription
        }
    }

    private func downloadAndOpen(item: SFTPItem) async {
        guard let sshInfo = sshConnectionInfo() else { return }
        transferProgress = TransferProgress(filename: item.name, type: .download, fraction: 0)

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nexus_sftp_\(UUID().uuidString)_\(item.name)")

        do {
            try await SFTPService.shared.downloadFile(
                host: sshInfo.host, port: sshInfo.port,
                username: sshInfo.username, password: sshInfo.password,
                keyPath: sshInfo.keyPath, remotePath: item.path, to: tempURL)
            transferProgress = nil
            NSWorkspace.shared.open(tempURL)
        } catch {
            transferProgress = nil
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItem(item: SFTPItem) async {
        guard let sshInfo = sshConnectionInfo() else { return }
        do {
            try await SFTPService.shared.delete(
                host: sshInfo.host, port: sshInfo.port,
                username: sshInfo.username, password: sshInfo.password,
                keyPath: sshInfo.keyPath, path: item.path, isDirectory: item.isDirectory)
            await loadDirectory(path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameItem(_ item: SFTPItem, to newName: String) async {
        guard let sshInfo = sshConnectionInfo(), !newName.isEmpty, newName != item.name else { return }
        let parent = item.path.components(separatedBy: "/").dropLast().joined(separator: "/") + "/"
        let newPath = parent + newName
        do {
            try await SFTPService.shared.rename(
                host: sshInfo.host, port: sshInfo.port,
                username: sshInfo.username, password: sshInfo.password,
                keyPath: sshInfo.keyPath, from: item.path, to: newPath)
            await loadDirectory(path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createFolder(name: String) async {
        guard let sshInfo = sshConnectionInfo(), !name.isEmpty else { return }
        let newPath = currentPath.hasSuffix("/") ? currentPath + name : currentPath + "/" + name
        do {
            try await SFTPService.shared.createDirectory(
                host: sshInfo.host, port: sshInfo.port,
                username: sshInfo.username, password: sshInfo.password,
                keyPath: sshInfo.keyPath, path: newPath)
            await loadDirectory(path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                guard let sshInfo = sshConnectionInfo() else { return }
                transferProgress = TransferProgress(filename: url.lastPathComponent, type: .upload, fraction: 0)
                let remotePath = (currentPath.hasSuffix("/") ? currentPath : currentPath + "/") + url.lastPathComponent
                do {
                    try await SFTPService.shared.uploadFile(
                        host: sshInfo.host, port: sshInfo.port,
                        username: sshInfo.username, password: sshInfo.password,
                        keyPath: sshInfo.keyPath, from: url, remotePath: remotePath)
                    transferProgress = nil
                    await loadDirectory(path: currentPath)
                } catch {
                    transferProgress = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - SSH Info helper

    private struct SSHInfo {
        let host: String
        let port: Int
        let username: String
        let password: String?
        let keyPath: String?
    }

    private func sshConnectionInfo() -> SSHInfo? {
        guard cs.session.connectionType == .ssh else { return nil }
        let session = cs.session

        // Parse "user@host" format in session.host — same logic as SSHArgumentBuilder
        var effectiveUser = session.username
        var effectiveHost = session.host
        if session.host.contains("@"), let atRange = session.host.range(of: "@", options: .backwards) {
            let parsedUser = String(session.host[..<atRange.lowerBound])
            let parsedHost = String(session.host[atRange.upperBound...])
            if effectiveUser.isEmpty { effectiveUser = parsedUser }
            effectiveHost = parsedHost
        }

        return SSHInfo(
            host: effectiveHost,
            port: session.port,
            username: effectiveUser,
            password: cs.sshPassword,
            keyPath: cs.tempKeyPath ?? (session.sshPrivateKeyPath.isEmpty ? nil : session.sshPrivateKeyPath)
        )
    }
}

// MARK: - Breadcrumb Navigation

struct BreadcrumbView: View {
    let path: String
    let onNavigate: (String) -> Void

    private var components: [(String, String)] {
        var parts: [(String, String)] = [("/", "/")]
        let segments = path.components(separatedBy: "/").filter { !$0.isEmpty }
        var accumulated = "/"
        for segment in segments {
            accumulated = accumulated.hasSuffix("/") ? accumulated + segment : accumulated + "/" + segment
            parts.append((segment, accumulated))
        }
        return parts
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button(component.0) {
                        onNavigate(component.1)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(index == components.count - 1 ? .primary : .secondary)
                }
            }
        }
    }
}

// MARK: - File Item Row

struct SFTPItemRow: View {
    let item: SFTPItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)

                if !item.isDirectory {
                    Text(formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(formattedDate)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        if item.isSymlink { return "link" }
        if item.isDirectory { return "folder.fill" }
        // File type by extension
        let ext = (item.name as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "log": return "doc.text"
        case "pdf": return "doc.fill"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "zip", "tar", "gz", "bz2", "xz": return "archivebox"
        case "sh", "bash", "zsh": return "terminal"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "xml", "conf", "cfg", "ini": return "doc.badge.gearshape"
        default: return "doc"
        }
    }

    private var iconColor: Color {
        if item.isDirectory { return .accentColor }
        if item.isSymlink { return .cyan }
        return .secondary
    }

    private var formattedSize: String {
        if item.isDirectory { return "" }
        let bytes = item.size
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: item.modifiedDate)
    }
}

// MARK: - Context Menu

struct SFTPContextMenu: View {
    let item: SFTPItem
    let onDownload: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onNewFolder: () -> Void

    var body: some View {
        if !item.isDirectory {
            Button("sftp.download") { onDownload() }
            Divider()
        }
        Button("sftp.rename") { onRename() }
        Button("sftp.new_folder") { onNewFolder() }
        Divider()
        Button("sftp.delete", role: .destructive) { onDelete() }
    }
}

// MARK: - Transfer Progress Overlay

struct TransferProgress {
    let filename: String
    enum TransferType { case upload, download }
    let type: TransferType
    var fraction: Double
}

struct TransferProgressOverlay: View {
    let progress: TransferProgress

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 12) {
                Image(systemName: progress.type == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                Text(progress.type == .upload ? String(localized: "sftp.uploading") : String(localized: "sftp.downloading"))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(progress.filename)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Rename Sheet

struct RenameSheet: View {
    @Binding var name: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("sftp.rename")
                .font(.headline)
            TextField("sftp.new_name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack {
                Button("action.cancel") { onCancel() }
                Button("action.save") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}
