import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var searchText = ""

    // Edit is only allowed when exactly one item is selected
    private var canEditSelected: Bool { vm.selectedSidebarItems.count == 1 }
    private var canDeleteSelected: Bool { !vm.selectedSidebarItems.isEmpty }

    // The folder currently selected (if any) — used as default for new sessions
    private var selectedFolder: Folder? {
        for item in vm.selectedSidebarItems {
            if case .folder(let f) = item { return f }
        }
        return nil
    }

    private func editSelected() {
        guard let item = vm.selectedSidebarItem else { return }
        switch item {
        case .session(let s): vm.editingSession = s
        case .folder(let f):  vm.editingFolder  = f
        }
    }

    private func deleteSelected() {
        vm.deleteSidebarSelection(vm.selectedSidebarItems)
    }

    var body: some View {
        @Bindable var vm = vm

        List(selection: $vm.selectedSidebarItems) {
            Section {
                ForEach(vm.childFolders(of: nil)) { folder in
                    FolderRow(folder: folder, depth: 0, searchText: searchText)
                }
                ForEach(vm.sessions(in: nil).filtered(by: searchText)) { session in
                    SessionRow(session: session)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar)
        .onDeleteCommand { deleteSelected() }
        .toolbar {
            // ── Add (leftmost, + icon) ──────────────────────────────
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        vm.addSessionParentFolderId = selectedFolder?.id
                        vm.showAddSession = true
                    } label: {
                        Label("sidebar.add_session", systemImage: "plus.circle")
                    }
                    Button {
                        vm.addSessionParentFolderId = selectedFolder?.id
                        vm.showAddFolder = true
                    } label: {
                        Label("sidebar.add_folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("action.add")
            }
            // ── Edit ────────────────────────────────────────────────
            ToolbarItem(placement: .automatic) {
                Button {
                    editSelected()
                } label: {
                    Image(systemName: "pencil")
                }
                .disabled(!canEditSelected)
                .help("action.edit")
                .keyboardShortcut("e", modifiers: .command)
            }
            // ── Delete ──────────────────────────────────────────────
            ToolbarItem(placement: .automatic) {
                Button {
                    deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(!canDeleteSelected)
                .help("action.delete")
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
        .sheet(isPresented: $vm.showAddSession) {
            AddSessionView(parentFolderId: vm.addSessionParentFolderId)
        }
        .sheet(isPresented: $vm.showAddFolder) {
            AddFolderView(parentFolderId: vm.addSessionParentFolderId)
        }
        .sheet(item: $vm.editingSession) { session in
            AddSessionView(session: session)
        }
        .sheet(item: $vm.editingFolder) { folder in
            AddFolderView(folder: folder)
        }
        .sheet(isPresented: $vm.showImportCSV) {
            ImportCSVView()
        }
    }
}

// MARK: - Folder row (recursive)

struct FolderRow: View {
    let folder: Folder
    let depth: Int
    let searchText: String
    @Environment(AppViewModel.self) private var vm

    private var childFolders: [Folder] { vm.childFolders(of: folder.id) }
    private var childSessions: [Session] { vm.sessions(in: folder.id).filtered(by: searchText) }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { folder.isExpanded },
            set: { newVal in
                var updated = folder
                updated.isExpanded = newVal
                vm.updateFolder(updated)
            }
        )) {
            ForEach(childFolders) { child in
                FolderRow(folder: child, depth: depth + 1, searchText: searchText)
            }
            ForEach(childSessions) { session in
                SessionRow(session: session)
            }
        } label: {
            Label(folder.name, systemImage: "folder")
                .tag(SidebarItem.folder(folder))
                // Context menu on label only — does NOT propagate to child rows
                .contextMenu {
                    Button {
                        vm.addSessionParentFolderId = folder.id
                        vm.showAddSession = true
                    } label: {
                        Label("sidebar.add_session", systemImage: "plus.circle")
                    }
                    Button {
                        vm.addSessionParentFolderId = folder.id
                        vm.showAddFolder = true
                    } label: {
                        Label("sidebar.add_subfolder", systemImage: "folder.badge.plus")
                    }
                    Divider()
                    Button {
                        vm.editingFolder = folder
                    } label: {
                        Label("action.edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        vm.deleteFolder(folder)
                    } label: {
                        Label("action.delete", systemImage: "trash")
                    }
                }
        }
    }
}

// MARK: - Session row

struct SessionRow: View {
    let session: Session
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.connectionType.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.name.isEmpty ? session.host : session.name)
                    .font(.body)
                    .lineLimit(1)
                if !session.description.isEmpty {
                    Text(session.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !session.host.isEmpty && !session.name.isEmpty {
                    Text(session.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tag(SidebarItem.session(session))
        // simultaneousGesture lets the List selection fire AND the double-tap fire
        // independently — onTapGesture(count:2) would sometimes eat single clicks
        .simultaneousGesture(TapGesture(count: 2).onEnded { vm.connect(to: session) })
        .contextMenu {
            Button {
                vm.connect(to: session)
            } label: {
                Label("action.connect", systemImage: "play.fill")
            }
            Divider()
            Button {
                vm.editingSession = session
            } label: {
                Label("action.edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                vm.deleteSession(session)
            } label: {
                Label("action.delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Filter helper

private extension [Session] {
    func filtered(by text: String) -> [Session] {
        guard !text.isEmpty else { return self }
        return filter {
            $0.name.localizedCaseInsensitiveContains(text) ||
            $0.host.localizedCaseInsensitiveContains(text) ||
            $0.username.localizedCaseInsensitiveContains(text) ||
            $0.description.localizedCaseInsensitiveContains(text)
        }
    }
}
