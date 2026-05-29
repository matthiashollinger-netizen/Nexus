import Foundation
import SwiftUI

// MARK: - FocusedValue for macro execution (sessions list, available in menus)

private struct MacroExecutorVMKey: FocusedValueKey {
    typealias Value = [ConnectionSession]
}

extension FocusedValues {
    var macroExecutorVM: [ConnectionSession]? {
        get { self[MacroExecutorVMKey.self] }
        set { self[MacroExecutorVMKey.self] = newValue }
    }
}

@Observable
final class AppViewModel {
    var folders: [Folder] = []
    var sessions: [Session] = []
    var credentials: [Credential] = []
    var settings: AppSettings = AppSettings()
    var activeSessions: [ConnectionSession] = []
    var selectedTabId: UUID? = nil

    // Sidebar selection (Set enables Cmd+Click / Shift+Click multi-select)
    var selectedSidebarItems: Set<SidebarItem> = []

    /// Convenience: the single selected item (for edit operations)
    var selectedSidebarItem: SidebarItem? { selectedSidebarItems.first }

    // Sheet / window state
    var showPasswordManager: Bool = false
    var showSettings: Bool = false
    var showImportCSV: Bool = false
    var showAddSession: Bool = false
    var showAddFolder: Bool = false
    var showBugReporter: Bool = false
    var showFeatureRequest: Bool = false
    var editingSession: Session? = nil
    var editingFolder: Folder? = nil
    var addSessionParentFolderId: UUID? = nil

    // SFTP Browser
    var showSFTPBrowser: Bool = false
    var sftpCurrentPath: String = "/"

    // Macro Manager
    var showMacroManager: Bool = false

    // Embedded Servers
    var showEmbeddedServers: Bool = false

    // Theme Editor
    var showThemeEditor: Bool = false

    // Unlock state
    var isUnlocked: Bool = false
    var masterPassword: String = ""
    var unlockError: String? = nil

    let db = DatabaseService()

    init() {
        loadData()
        // If no master password configured, treat as unlocked
        if !settings.masterPasswordEnabled {
            isUnlocked = true
        }
        // ── Service lifecycle ─────────────────────────────────────────────
        // All singletons are lazy — boot them here so persisted data loads
        // and hotkey monitors are active before the first view renders.
        ThemeService.shared.loadThemes()
        MacroService.shared.loadMacros()
        EmbeddedServerService.shared.loadServers()
        // Hotkey monitor needs a live reference to activeSessions.
        // The closure is retained weakly to avoid a retain cycle.
        MacroService.shared.installHotkeyMonitor { [weak self] in
            self?.activeSessions ?? []
        }
    }

    // MARK: - Load

    func loadData() {
        folders = db.loadFolders()
        sessions = db.loadSessions()
        settings = db.loadSettings()
    }

    func unlock(password: String) {
        do {
            credentials = try db.loadCredentials(masterPassword: password)
            masterPassword = password
            isUnlocked = true
            unlockError = nil
        } catch {
            unlockError = error.localizedDescription
        }
    }

    func saveSettings() {
        db.saveSettings(settings)
    }

    // MARK: - Folders

    func addFolder(name: String, parentId: UUID?) {
        var folder = Folder()
        folder.name = name
        folder.parentId = parentId
        folder.sortOrder = folders.count
        folders.append(folder)
        db.saveFolders(folders)
    }

    func updateFolder(_ folder: Folder) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx] = folder
        db.saveFolders(folders)
    }

    func deleteFolder(_ folder: Folder) {
        // Recursively delete children
        childFolders(of: folder.id).forEach { deleteFolder($0) }
        sessions.removeAll { $0.folderId == folder.id }
        folders.removeAll { $0.id == folder.id }
        db.saveFolders(folders)
        db.saveSessions(sessions)
    }

    // MARK: - Sessions

    func addSession(_ session: Session) {
        sessions.append(session)
        db.saveSessions(sessions)
    }

    func updateSession(_ session: Session) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx] = session
        db.saveSessions(sessions)
    }

    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        db.saveSessions(sessions)
    }

    func deleteSidebarSelection(_ items: Set<SidebarItem>) {
        for item in items {
            switch item {
            case .session(let s): sessions.removeAll { $0.id == s.id }
            case .folder(let f): deleteFolderRecursive(f)
            }
        }
        db.saveSessions(sessions)
        db.saveFolders(folders)
        selectedSidebarItems.removeAll()
    }

    private func deleteFolderRecursive(_ folder: Folder) {
        childFolders(of: folder.id).forEach { deleteFolderRecursive($0) }
        sessions.removeAll { $0.folderId == folder.id }
        folders.removeAll { $0.id == folder.id }
    }

    // MARK: - Connect / Disconnect

    func connect(to session: Session) {
        let cred = credential(for: session)
        let cs = ConnectionSession(session: session, credential: cred, settings: settings)
        activeSessions.append(cs)
        selectedTabId = cs.id
        // Run on-connect macros and refresh schedules for new session count
        MacroService.shared.runOnConnectMacros(for: cs)
        MacroService.shared.scheduleAllMacros(activeSessions: activeSessions)
    }

    func closeSession(_ cs: ConnectionSession) {
        cs.disconnect()
        if selectedTabId == cs.id {
            selectedTabId = activeSessions.last(where: { $0.id != cs.id })?.id
        }
        activeSessions.removeAll { $0.id == cs.id }
        // Refresh schedules — removed session should no longer receive macros
        MacroService.shared.scheduleAllMacros(activeSessions: activeSessions)
    }

    /// Moves a tab to the given insertion index (used by DragGesture tab reorder).
    /// `toIndex` is the "insert before" position in the ORIGINAL array.
    func moveTabToIndex(id: UUID, toIndex: Int) {
        guard let fromIdx = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        let clampedTo = max(0, min(activeSessions.count, toIndex))
        guard clampedTo != fromIdx else { return }
        let item = activeSessions.remove(at: fromIdx)
        // After removal, indices shift: if target was after source, subtract 1
        let insertIdx = fromIdx < clampedTo ? clampedTo - 1 : clampedTo
        activeSessions.insert(item, at: insertIdx)
    }

    /// Replaces the disconnected/failed session with a fresh one at the same tab position.
    func reconnect(cs: ConnectionSession) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == cs.id }) else { return }
        cs.disconnect()
        let newCs = ConnectionSession(session: cs.session, credential: credential(for: cs.session), settings: settings)
        activeSessions[idx] = newCs
        selectedTabId = newCs.id
    }

    // MARK: - Credentials

    func addCredential(_ credential: Credential) {
        credentials.append(credential)
        saveCredentialsSilently()
    }

    func updateCredential(_ credential: Credential) {
        guard let idx = credentials.firstIndex(where: { $0.id == credential.id }) else { return }
        var updated = credential
        updated.updatedAt = Date()
        credentials[idx] = updated
        saveCredentialsSilently()
    }

    func deleteCredential(_ credential: Credential) {
        credentials.removeAll { $0.id == credential.id }
        saveCredentialsSilently()
    }

    private func saveCredentialsSilently() {
        guard settings.masterPasswordEnabled else { return }
        try? db.saveCredentials(credentials, masterPassword: masterPassword)
    }

    // MARK: - Helpers

    func childFolders(of parentId: UUID?) -> [Folder] {
        folders.filter { $0.parentId == parentId }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func sessions(in folderId: UUID?) -> [Session] {
        sessions.filter { $0.folderId == folderId }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func credential(for session: Session) -> Credential? {
        if let credId = session.credentialId {
            return credentials.first { $0.id == credId }
        }
        // Inherit from folder chain
        var folderId = session.folderId
        while let fid = folderId {
            guard let folder = folders.first(where: { $0.id == fid }) else { break }
            if let credId = folder.credentialId {
                return credentials.first { $0.id == credId }
            }
            folderId = folder.parentId
        }
        return nil
    }

    // MARK: - Drag & Drop — Move / Reorder

    /// Move history for ⌘Z undo (each entry = one drag operation)
    private struct MoveSnapshot {
        let sessionsBefore: [Session]
        let foldersBefore:  [Folder]
    }
    private var moveHistory: [MoveSnapshot] = []

    /// Moves a session or folder to a new parent folder (or root if `nil`).
    func moveSidebarItem(id: UUID, isFolder: Bool, toFolderId: UUID?) {
        let snapshot = MoveSnapshot(sessionsBefore: sessions, foldersBefore: folders)

        if isFolder {
            guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
            // Guard against circular nesting (can't move folder into itself or its descendant)
            guard !isFolderDescendant(potentialChild: toFolderId, of: id) else { return }
            folders[idx].parentId = toFolderId
            // Append at end of target level
            let maxOrder = folders.filter { $0.parentId == toFolderId }.map(\.sortOrder).max() ?? -1
            folders[idx].sortOrder = maxOrder + 1
        } else {
            guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
            sessions[idx].folderId = toFolderId
            let maxOrder = sessions.filter { $0.folderId == toFolderId }.map(\.sortOrder).max() ?? -1
            sessions[idx].sortOrder = maxOrder + 1
        }

        db.saveSessions(sessions)
        db.saveFolders(folders)
        moveHistory.append(snapshot)
    }

    /// Reorders sessions within the same folder level.
    func reorderSessions(folderId: UUID?, from: IndexSet, to: Int) {
        let snapshot = MoveSnapshot(sessionsBefore: sessions, foldersBefore: folders)
        var level = sessions.filter { $0.folderId == folderId }.sorted { $0.sortOrder < $1.sortOrder }
        level.move(fromOffsets: from, toOffset: to)
        for (i, s) in level.enumerated() {
            if let idx = sessions.firstIndex(where: { $0.id == s.id }) {
                sessions[idx].sortOrder = i
            }
        }
        db.saveSessions(sessions)
        moveHistory.append(snapshot)
    }

    /// Reorders folders within the same parent level.
    func reorderFolders(parentId: UUID?, from: IndexSet, to: Int) {
        let snapshot = MoveSnapshot(sessionsBefore: sessions, foldersBefore: folders)
        var level = folders.filter { $0.parentId == parentId }.sorted { $0.sortOrder < $1.sortOrder }
        level.move(fromOffsets: from, toOffset: to)
        for (i, f) in level.enumerated() {
            if let idx = folders.firstIndex(where: { $0.id == f.id }) {
                folders[idx].sortOrder = i
            }
        }
        db.saveFolders(folders)
        moveHistory.append(snapshot)
    }

    /// Undo last move / reorder operation.
    func undoLastMove() {
        guard let snapshot = moveHistory.popLast() else { return }
        sessions = snapshot.sessionsBefore
        folders  = snapshot.foldersBefore
        db.saveSessions(sessions)
        db.saveFolders(folders)
    }

    var canUndoMove: Bool { !moveHistory.isEmpty }

    // Guard: returns true if `potentialChild` is nil or a descendant of `ancestor`
    private func isFolderDescendant(potentialChild id: UUID?, of ancestor: UUID) -> Bool {
        guard let id else { return false }
        if id == ancestor { return true }
        guard let folder = folders.first(where: { $0.id == id }) else { return false }
        return isFolderDescendant(potentialChild: folder.parentId, of: ancestor)
    }

    // MARK: - Batch import (from column-mapped CSV)

    func addImportedData(sessions newSessions: [Session], folders newFolders: [Folder], credentials newCreds: [Credential]) {
        folders.append(contentsOf: newFolders)
        credentials.append(contentsOf: newCreds)
        sessions.append(contentsOf: newSessions)
        db.saveFolders(self.folders)
        db.saveSessions(self.sessions)
        if settings.masterPasswordEnabled && !masterPassword.isEmpty {
            try? db.saveCredentials(self.credentials, masterPassword: masterPassword)
        }
    }

    // MARK: - CSV Import (Termius format, legacy)

    func importCSV(_ content: String) {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return }

        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            guard fields.count >= 5 else { continue }

            let groupName = fields[safe: 0] ?? ""
            let label     = fields[safe: 1] ?? ""
            let host      = fields[safe: 3] ?? ""
            let proto     = (fields[safe: 4] ?? "ssh").lowercased()
            let portStr   = fields[safe: 5] ?? ""
            let user      = fields[safe: 6] ?? ""

            guard !host.isEmpty else { continue }

            var folderId: UUID? = nil
            if !groupName.isEmpty {
                if let existing = folders.first(where: { $0.name == groupName && $0.parentId == nil }) {
                    folderId = existing.id
                } else {
                    var folder = Folder()
                    folder.name = groupName
                    folders.append(folder)
                    folderId = folder.id
                }
            }

            let connType: ConnectionType = {
                switch proto {
                case "telnet": return .telnet
                case "serial": return .serial
                default: return .ssh
                }
            }()

            var s = Session()
            s.name = label.isEmpty ? host : label
            s.host = host
            s.port = Int(portStr) ?? connType.defaultPort
            s.username = user
            s.connectionType = connType
            s.folderId = folderId
            sessions.append(s)
        }

        db.saveFolders(folders)
        db.saveSessions(sessions)
    }

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

// MARK: - Sidebar item
// Equality and hash are based on ID only so that selection survives session/folder edits.

enum SidebarItem {
    case folder(Folder)
    case session(Session)
}

extension SidebarItem: Equatable {
    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        switch (lhs, rhs) {
        case (.session(let a), .session(let b)): return a.id == b.id
        case (.folder(let a),  .folder(let b)):  return a.id == b.id
        default: return false
        }
    }
}

extension SidebarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .session(let s): hasher.combine(0); hasher.combine(s.id)
        case .folder(let f):  hasher.combine(1); hasher.combine(f.id)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
