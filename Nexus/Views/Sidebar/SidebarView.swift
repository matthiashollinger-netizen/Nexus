import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Sidebar drag & drop
//
// WHY THIS DESIGN (read before changing — the click handling has regressed 3×):
//
//  1. SINGLE-CLICK must select the whole row. The killer was `.onDrag`/`.draggable`
//     applied to the ROW CONTENT — on macOS that steals the List's single-click
//     selection on exactly the area it covers (so only the leading inset "beside the
//     text" still selected). FIX: the drag source `.onDrag` lives ONLY on a small
//     trailing grip handle, never on the selectable text. The row content stays a
//     clean List selection target via `.contentShape(Rectangle())`.
//
//  2. DOUBLE-CLICK must open the row UNDER THE CURSOR. The killer was a GLOBAL
//     NSEvent monitor that connected `vm.selectedSidebarItem` — i.e. whatever was
//     already selected, not what was double-clicked. FIX: a per-row
//     `simultaneousGesture(TapGesture(count: 2))` that captures THIS row's session,
//     so it is always the correct item. No global state, no monitor.
//
//  3. VISIBLE DROP INDICATOR: each row is a drop target; while hovered it publishes
//     itself to `SidebarDragModel` which draws an accent insertion line (reorder) or
//     a folder highlight (move-into). No reliance on `.onMove`'s opaque native line.

enum SidebarDragPayload {
    static func encode(id: UUID, isFolder: Bool) -> String {
        "\(isFolder ? "folder" : "session"):\(id.uuidString)"
    }
    static func decode(_ string: String) -> (id: UUID, isFolder: Bool)? {
        let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        return (id, parts[0] == "folder")
    }
    static func itemProvider(id: UUID, isFolder: Bool) -> NSItemProvider {
        NSItemProvider(object: encode(id: id, isFolder: isFolder) as NSString)
    }
}

/// Shared, observable drag state so rows can render the insertion line / highlight.
@Observable final class SidebarDragModel {
    var insertBeforeId: UUID? = nil   // draw an accent line above this row
    var intoFolderId: UUID? = nil     // highlight this folder (move-into)
    var onRoot: Bool = false          // highlight the root drop area
}

/// Drop target for "insert before this row" (reorder within the row's level).
struct RowReorderDropDelegate: DropDelegate {
    let targetId: UUID
    let targetIsFolder: Bool
    let targetParentId: UUID?     // the folder the target lives in
    let vm: AppViewModel
    let model: SidebarDragModel

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }
    func dropEntered(info: DropInfo) { model.insertBeforeId = targetId; model.intoFolderId = nil; model.onRoot = false }
    func dropExited(info: DropInfo)  { if model.insertBeforeId == targetId { model.insertBeforeId = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.insertBeforeId = nil
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let s = object as? String, let p = SidebarDragPayload.decode(s) else { return }
            guard p.id != targetId else { return }   // can't drop onto self
            DispatchQueue.main.async {
                vm.moveSidebarItem(id: p.id, isFolder: p.isFolder,
                                   toFolderId: targetParentId, before: (targetId, targetIsFolder))
            }
        }
        return true
    }
}

/// Drop target for "move into this folder".
struct FolderIntoDropDelegate: DropDelegate {
    let folderId: UUID
    let vm: AppViewModel
    let model: SidebarDragModel

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }
    func dropEntered(info: DropInfo) { model.intoFolderId = folderId; model.insertBeforeId = nil; model.onRoot = false }
    func dropExited(info: DropInfo)  { if model.intoFolderId == folderId { model.intoFolderId = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.intoFolderId = nil
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let s = object as? String, let p = SidebarDragPayload.decode(s) else { return }
            DispatchQueue.main.async {
                vm.moveSidebarItem(id: p.id, isFolder: p.isFolder, toFolderId: folderId, before: nil)
            }
        }
        return true
    }
}

/// Drop target for the root area (move to top level).
struct RootDropDelegate: DropDelegate {
    let vm: AppViewModel
    let model: SidebarDragModel

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }
    func dropEntered(info: DropInfo) { model.onRoot = true }
    func dropExited(info: DropInfo)  { model.onRoot = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.onRoot = false
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let s = object as? String, let p = SidebarDragPayload.decode(s) else { return }
            DispatchQueue.main.async {
                vm.moveSidebarItem(id: p.id, isFolder: p.isFolder, toFolderId: nil, before: nil)
            }
        }
        return true
    }
}

/// A small trailing grip the user drags to move a row. `.onDrag` lives HERE only,
/// never on the row's selectable content — so single-click selection keeps working.
struct SidebarDragHandle: View {
    let id: UUID
    let isFolder: Bool

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .onDrag { SidebarDragPayload.itemProvider(id: id, isFolder: isFolder) }
            .help("sidebar.drag_hint")
    }
}

// MARK: - Sidebar root

struct SidebarView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var searchText = ""
    @State private var dragModel = SidebarDragModel()

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
                // Root-level folders
                ForEach(vm.childFolders(of: nil)) { folder in
                    FolderRow(folder: folder, depth: 0, searchText: searchText)
                }
                // Root-level sessions
                ForEach(vm.sessions(in: nil).filtered(by: searchText)) { session in
                    SessionRow(session: session, parentFolderId: nil)
                }
            }
        }
        .listStyle(.sidebar)
        .environment(dragModel)
        .searchable(text: $searchText, placement: .sidebar)
        // Drop onto the root area (outside any folder) → move to top level.
        .onDrop(of: [.text], delegate: RootDropDelegate(vm: vm, model: dragModel))
        .overlay(alignment: .bottom) {
            if dragModel.onRoot {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDeleteCommand { deleteSelected() }
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
    @Environment(SidebarDragModel.self) private var dragModel

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
            ForEach(childFolders) { child in
                FolderRow(folder: child, depth: depth + 1, searchText: searchText)
            }
            ForEach(childSessions) { session in
                SessionRow(session: session, parentFolderId: folder.id)
            }
        } label: {
            HStack(spacing: 6) {
                Label(folder.name, systemImage: "folder")
                Spacer(minLength: 0)
                SidebarDragHandle(id: folder.id, isFolder: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())   // whole row selectable, incl. the text
            .tag(SidebarItem.folder(folder))
            .background(dragModel.intoFolderId == folder.id ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            // Insertion line above the folder (reorder within its level)
            .overlay(alignment: .top) {
                if dragModel.insertBeforeId == folder.id { InsertionLine() }
            }
            // Dropping ONTO a folder moves the item INTO it.
            .onDrop(of: [.text], delegate: FolderIntoDropDelegate(
                folderId: folder.id, vm: vm, model: dragModel))
            // Double-click connects... folders aren't connectable, so just toggle expand.
            .contextMenu {
                Button {
                    vm.addSessionParentFolderId = folder.id
                    vm.showAddSession = true
                } label: { Label("sidebar.add_session", systemImage: "plus.circle") }
                Button {
                    vm.addSessionParentFolderId = folder.id
                    vm.showAddFolder = true
                } label: { Label("sidebar.add_subfolder", systemImage: "folder.badge.plus") }
                Divider()
                Button { vm.editingFolder = folder } label: { Label("action.edit", systemImage: "pencil") }
                Button(role: .destructive) { vm.deleteFolder(folder) } label: {
                    Label("action.delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Session row

struct SessionRow: View {
    let session: Session
    let parentFolderId: UUID?
    @Environment(AppViewModel.self) private var vm
    @Environment(SidebarDragModel.self) private var dragModel

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
            SidebarDragHandle(id: session.id, isFolder: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())   // entire row (incl. text) is the single-click target
        .tag(SidebarItem.session(session))
        // DOUBLE-CLICK: per-row gesture → always connects THIS session (never the
        // previously-selected one). simultaneousGesture coexists with List single-click
        // selection. This is the permanent fix for the recurring "wrong item" bug.
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            vm.connect(to: session)
        })
        // Insertion line above this row (reorder within the level)
        .overlay(alignment: .top) {
            if dragModel.insertBeforeId == session.id { InsertionLine() }
        }
        // Dropping ONTO a session inserts the dragged item before it (reorder).
        .onDrop(of: [.text], delegate: RowReorderDropDelegate(
            targetId: session.id, targetIsFolder: false,
            targetParentId: parentFolderId, vm: vm, model: dragModel))
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

// MARK: - Insertion line indicator (the visible "STRICH")

private struct InsertionLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6).offset(x: -2)
            }
            .allowsHitTesting(false)
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
