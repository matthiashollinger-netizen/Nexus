import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Transfer type for Drag & Drop

extension UTType {
    static let nexusSidebarItem = UTType("com.hollinger.Nexus.sidebarItem")!
}

struct SidebarTransferItem: Transferable, Codable {
    let id: UUID
    let isFolder: Bool

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .nexusSidebarItem)
    }
}

// MARK: - Sidebar root

struct SidebarView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var searchText = ""
    @State private var isRootDropTargeted = false

    private var canEditSelected:  Bool { vm.selectedSidebarItems.count == 1 }
    private var canDeleteSelected: Bool { !vm.selectedSidebarItems.isEmpty }

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
                // Root-level folders (reorderable)
                ForEach(vm.childFolders(of: nil)) { folder in
                    FolderRow(folder: folder, depth: 0, searchText: searchText)
                }
                .onMove { from, to in
                    vm.reorderFolders(parentId: nil, from: from, to: to)
                }

                // Root-level sessions (reorderable)
                ForEach(vm.sessions(in: nil).filtered(by: searchText)) { session in
                    SessionRow(session: session)
                }
                .onMove { from, to in
                    vm.reorderSessions(folderId: nil, from: from, to: to)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar)
        // Drop onto root (outside any folder) → move item to top level
        .dropDestination(for: SidebarTransferItem.self) { items, _ in
            for item in items {
                vm.moveSidebarItem(id: item.id, isFolder: item.isFolder, toFolderId: nil)
            }
            return !items.isEmpty
        } isTargeted: { targeted in
            isRootDropTargeted = targeted
        }
        .overlay(alignment: .bottom) {
            if isRootDropTargeted {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDeleteCommand { deleteSelected() }
        .background(SidebarDoubleClickMonitor {
            if let item = vm.selectedSidebarItem, case .session(let s) = item {
                vm.connect(to: s)
            }
        })
        .toolbar {
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
            ToolbarItem(placement: .automatic) {
                Button { editSelected() } label: { Image(systemName: "pencil") }
                    .disabled(!canEditSelected)
                    .help("action.edit")
                    .keyboardShortcut("e", modifiers: .command)
            }
            ToolbarItem(placement: .automatic) {
                Button { deleteSelected() } label: { Image(systemName: "trash") }
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
        .sheet(item: $vm.editingSession) { session in AddSessionView(session: session) }
        .sheet(item: $vm.editingFolder)  { folder  in AddFolderView(folder: folder) }
        .sheet(isPresented: $vm.showImportCSV) { ImportCSVView() }
        // ⌘Z undo for drag moves
        .focusedValue(\.sidebarUndoVM, vm.canUndoMove ? vm : nil)
    }
}

// MARK: - Focused Value for undo

private struct SidebarUndoVMKey: FocusedValueKey {
    typealias Value = AppViewModel
}

extension FocusedValues {
    var sidebarUndoVM: AppViewModel? {
        get { self[SidebarUndoVMKey.self] }
        set { self[SidebarUndoVMKey.self] = newValue }
    }
}

// MARK: - Folder row (recursive, supports drop)

struct FolderRow: View {
    let folder: Folder
    let depth: Int
    let searchText: String
    @Environment(AppViewModel.self) private var vm
    @State private var isDropTargeted = false

    private var childFolders: [Folder] { vm.childFolders(of: folder.id) }
    private var childSessions: [Session] { vm.sessions(in: folder.id).filtered(by: searchText) }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { folder.isExpanded },
            set: { newVal in
                var updated = folder; updated.isExpanded = newVal
                vm.updateFolder(updated)
            }
        )) {
            // Child folders (reorderable within this folder)
            ForEach(childFolders) { child in
                FolderRow(folder: child, depth: depth + 1, searchText: searchText)
            }
            .onMove { from, to in
                vm.reorderFolders(parentId: folder.id, from: from, to: to)
            }

            // Child sessions (reorderable within this folder)
            ForEach(childSessions) { session in
                SessionRow(session: session)
            }
            .onMove { from, to in
                vm.reorderSessions(folderId: folder.id, from: from, to: to)
            }
        } label: {
            Label(folder.name, systemImage: "folder")
                .tag(SidebarItem.folder(folder))
                .background(isDropTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
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
                    Button { vm.editingFolder = folder } label: {
                        Label("action.edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) { vm.deleteFolder(folder) } label: {
                        Label("action.delete", systemImage: "trash")
                    }
                }
        }
        // This folder is a drop target — items dropped here move into it
        .dropDestination(for: SidebarTransferItem.self) { items, _ in
            for item in items {
                vm.moveSidebarItem(id: item.id, isFolder: item.isFolder, toFolderId: folder.id)
            }
            return !items.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        // This folder itself is draggable
        .draggable(SidebarTransferItem(id: folder.id, isFolder: true))
    }
}

// MARK: - Session row (draggable)

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
                    Text(session.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if !session.host.isEmpty && !session.name.isEmpty {
                    Text(session.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tag(SidebarItem.session(session))
        .draggable(SidebarTransferItem(id: session.id, isFolder: false))
        .contextMenu {
            Button { vm.connect(to: session) } label: {
                Label("action.connect", systemImage: "play.fill")
            }
            Divider()
            Button { vm.editingSession = session } label: {
                Label("action.edit", systemImage: "pencil")
            }
            Button(role: .destructive) { vm.deleteSession(session) } label: {
                Label("action.delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Double-click detector

private struct SidebarDoubleClickMonitor: NSViewRepresentable {
    let onDoubleClick: () -> Void
    func makeNSView(context: Context) -> NSView { context.coordinator.placeholder }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDoubleClick = onDoubleClick
    }
    func makeCoordinator() -> Coordinator { Coordinator(onDoubleClick: onDoubleClick) }

    final class Coordinator {
        let placeholder = NSView()
        var onDoubleClick: (() -> Void)?
        private var monitor: Any?

        init(onDoubleClick: @escaping () -> Void) {
            self.onDoubleClick = onDoubleClick
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard event.clickCount == 2,
                      let host = self?.placeholder,
                      let win  = host.window,
                      event.window === win else { return event }
                let click = event.locationInWindow
                let frame = host.convert(host.bounds, to: nil)
                if frame.contains(click) {
                    DispatchQueue.main.async { self?.onDoubleClick?() }
                }
                return event
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
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
