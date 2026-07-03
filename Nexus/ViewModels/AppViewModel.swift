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

    // Command Palette (⌘K)
    var showCommandPalette: Bool = false

    // A connect requested by a nexus://connect link. Held pending an explicit user
    // confirmation so a crafted link can't silently dial an arbitrary host.
    var pendingURLConnect: Session? = nil

    // Shown once, when a credential save first upgrades a pre-3.0.3 (HKDF) vault to the
    // new PBKDF2 format — so the user knows older Nexus versions can no longer open it.
    var showCredentialFormatUpgradeNotice: Bool = false

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
        // Restore saved syntax highlighting ruleset selection
        TerminalHighlighter.shared.updateEnabledRulesets(settings.enabledHighlightRulesets)
        // Hotkey monitor needs a live reference to activeSessions.
        // The closure is retained weakly to avoid a retain cycle.
        MacroService.shared.installHotkeyMonitor { [weak self] in
            self?.activeSessions ?? []
        }
        // Disconnect notifications (native macOS Notification Center).
        NotificationService.shared.enabled = settings.notifyOnDisconnect
        NotificationService.shared.requestAuthorizationIfNeeded()
        // SEC-6: remove temp private-key / askpass files orphaned by a previous crash.
        Self.cleanupOrphanedTempFiles()
    }

    /// Deletes leftover `nexus_key_*` and `nexus_askpass_*` / `nexus_sftp_*` files in
    /// the temp directory that a crash may have prevented from being cleaned up.
    private static func cleanupOrphanedTempFiles() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let prefixes = ["nexus_key_", "nexus_askpass_", "nexus_sftp_"]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil)) ?? []
        for url in entries where prefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Load

    func loadData() {
        folders = db.loadFolders()
        sessions = db.loadSessions()
        settings = db.loadSettings()
        // Snapshot the last-good state at launch so a crash/corruption is recoverable.
        db.createBackup(force: true)
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
        NotificationService.shared.enabled = settings.notifyOnDisconnect
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
        // Resolve RDP-specific credential (separate from the SSH credential)
        if session.connectionType == .rdp, let rdpCredId = session.rdpCredentialId {
            cs.rdpPassword = credentials.first { $0.id == rdpCredId }?.password
        } else if session.connectionType == .rdp {
            // Fall back to the inherited credential's password
            cs.rdpPassword = cred?.password
        }
        activeSessions.append(cs)
        selectedTabId = cs.id
        recordRecent(session)
        // Run on-connect macros and refresh schedules for new session count
        MacroService.shared.runOnConnectMacros(for: cs)
        MacroService.shared.scheduleAllMacros(activeSessions: activeSessions)

        // Per-session "run macro on connect" — delayed so the terminal/PTY is up
        // and the shell prompt is likely ready before commands are sent.
        if let macroId = session.macroOnConnectId,
           let macro = MacroService.shared.macros.first(where: { $0.id == macroId }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak cs] in
                guard let cs else { return }
                MacroService.shared.executeMacro(macro, in: [cs])
            }
        }
    }

    /// Connects all sessions flagged `autoConnectOnLaunch`. Called once after launch.
    func connectAutoSessions() {
        for session in sessions where session.autoConnectOnLaunch {
            // Avoid duplicate tabs if already connected.
            if !activeSessions.contains(where: { $0.session.id == session.id }) {
                connect(to: session)
            }
        }
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
        // Fully orphan the old session FIRST so a lingering macro/snippet send or a
        // late processTerminated callback can't reach the replaced terminal.
        cs.terminalSendHandler = nil
        cs.terminalNSView = nil
        cs.disconnect()
        let newCs = ConnectionSession(session: cs.session, credential: credential(for: cs.session), settings: settings)
        activeSessions[idx] = newCs
        selectedTabId = newCs.id
    }

    // MARK: - Live status / Recents / Favorites

    /// The live connection state for a session if it currently has an open tab.
    /// Drives the sidebar status dots, dashboard badges and palette rows.
    func liveState(for session: Session) -> ConnectionState? {
        activeSessions.first(where: { $0.session.id == session.id })?.state
    }

    /// Records a session as recently used (most-recent first, de-duped, capped).
    private func recordRecent(_ session: Session) {
        settings.recentSessionIds.removeAll { $0 == session.id }
        settings.recentSessionIds.insert(session.id, at: 0)
        if settings.recentSessionIds.count > 8 {
            settings.recentSessionIds = Array(settings.recentSessionIds.prefix(8))
        }
        saveSettings()
    }

    /// Recently-connected sessions, most-recent first (stale ids are dropped).
    var recentSessions: [Session] {
        settings.recentSessionIds.compactMap { id in sessions.first { $0.id == id } }
    }

    /// Sessions the user has starred.
    var favoriteSessions: [Session] {
        sessions.filter { $0.isFavorite }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func toggleFavorite(_ session: Session) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx].isFavorite.toggle()
        db.saveSessions(sessions)
    }

    // MARK: - MultiExec (broadcast input to several terminals at once)

    /// When on, a command typed in the broadcast bar is sent to every selected tab.
    var multiExecMode = false
    /// Tabs that receive broadcast input.
    var selectedExecTabs: Set<UUID> = []

    func toggleMultiExec() {
        multiExecMode.toggle()
        // Default to broadcasting to every open tab; clear when leaving the mode.
        selectedExecTabs = multiExecMode ? Set(activeSessions.map { $0.id }) : []
    }

    func toggleExecMembership(_ id: UUID) {
        if selectedExecTabs.contains(id) { selectedExecTabs.remove(id) }
        else { selectedExecTabs.insert(id) }
    }

    /// The tabs that will actually receive a broadcast (selected ∩ still open).
    var broadcastTargets: [ConnectionSession] {
        activeSessions.filter { selectedExecTabs.contains($0.id) }
    }

    /// Sends `text` followed by a newline to every selected, still-open tab.
    func broadcast(_ text: String) {
        let bytes = Array((text + "\n").utf8)
        for cs in broadcastTargets { cs.terminalSendHandler?(bytes) }
    }

    // MARK: - Snippets

    /// Session whose snippets are being edited (drives the SnippetEditor sheet).
    var editingSnippetsSession: Session? = nil

    /// The connection session shown in the foreground tab, if any.
    var activeConnection: ConnectionSession? {
        activeSessions.first { $0.id == selectedTabId }
    }

    /// Sends a snippet's command into the live terminal of `cs`.
    func sendSnippet(_ snippet: Snippet, to cs: ConnectionSession) {
        let text = snippet.command + (snippet.sendReturn ? "\n" : "")
        cs.terminalSendHandler?(Array(text.utf8))
    }

    // MARK: - URL scheme (nexus://)
    //
    // Deep links to open/connect a session from a browser, wiki or chat:
    //   nexus://open/<session-uuid>          — connect a saved session by id
    //   nexus://open?name=<name>             — connect a saved session by name
    //   nexus://connect?host=H&port=P&user=U&type=ssh|telnet|serial — ad-hoc connect
    func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "nexus", isUnlocked else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }

        switch url.host?.lowercased() {
        case "open":
            let idString = url.pathComponents.dropFirst().first ?? q("id")
            if let idString, let uuid = UUID(uuidString: idString),
               let session = sessions.first(where: { $0.id == uuid }) {
                connect(to: session)
            } else if let name = q("name"),
                      let session = sessions.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                connect(to: session)
            }
        case "connect":
            guard let host = q("host"), !host.isEmpty else { return }
            var session = Session()
            session.host = host
            session.name = q("name") ?? host
            session.username = q("user") ?? q("username") ?? ""
            let type = (q("type") ?? "ssh").lowercased()
            session.connectionType = (type == "telnet") ? .telnet : (type == "serial" ? .serial : .ssh)
            session.port = Int(q("port") ?? "") ?? session.connectionType.defaultPort
            // Don't auto-dial a host handed to us by a link — a crafted nexus://connect
            // could otherwise probe internal hosts or phish. Ask first.
            pendingURLConnect = session
        default:
            break
        }
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
        // Never persist with an empty master password (e.g. the unlock screen was
        // skipped) — that would overwrite the real vault with an empty-password blob.
        guard settings.masterPasswordEnabled, !masterPassword.isEmpty else { return }
        // Check BEFORE writing: saveCredentials always writes PBKDF2 (V2), so if the
        // store is currently legacy this save is the one-time format upgrade.
        let wasLegacy = db.credentialStoreIsLegacy()
        try? db.saveCredentials(credentials, masterPassword: masterPassword)
        if wasLegacy { showCredentialFormatUpgradeNotice = true }
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
        moveSidebarItem(id: id, isFolder: isFolder, toFolderId: toFolderId, before: nil)
    }

    /// Moves an item to `toFolderId` and, if `before` is given, positions it directly
    /// before that target item within the level (so drag-to-reorder lands precisely).
    func moveSidebarItem(id: UUID, isFolder: Bool, toFolderId: UUID?,
                         before: (id: UUID, isFolder: Bool)?) {
        let snapshot = MoveSnapshot(sessionsBefore: sessions, foldersBefore: folders)

        if isFolder {
            guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
            // Guard against circular nesting (can't move folder into itself or a descendant)
            guard !isFolderDescendant(potentialChild: toFolderId, of: id) else { return }
            folders[idx].parentId = toFolderId
            reorderLevelFolders(parentId: toFolderId, movedId: id,
                                beforeId: (before?.isFolder == true) ? before?.id : nil)
        } else {
            guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
            sessions[idx].folderId = toFolderId
            reorderLevelSessions(folderId: toFolderId, movedId: id,
                                 beforeId: (before?.isFolder == false) ? before?.id : nil)
        }

        db.saveSessions(sessions)
        db.saveFolders(folders)
        moveHistory.append(snapshot)
    }

    /// Renumbers sortOrder for sessions in `folderId`, placing `movedId` just before
    /// `beforeId` (or at the end if `beforeId` is nil/not found).
    private func reorderLevelSessions(folderId: UUID?, movedId: UUID, beforeId: UUID?) {
        var level = sessions.filter { $0.folderId == folderId }.sorted { $0.sortOrder < $1.sortOrder }
        level.removeAll { $0.id == movedId }
        guard let moved = sessions.first(where: { $0.id == movedId }) else { return }
        if let beforeId, let targetIdx = level.firstIndex(where: { $0.id == beforeId }) {
            level.insert(moved, at: targetIdx)
        } else {
            level.append(moved)
        }
        for (i, s) in level.enumerated() {
            if let idx = sessions.firstIndex(where: { $0.id == s.id }) { sessions[idx].sortOrder = i }
        }
    }

    private func reorderLevelFolders(parentId: UUID?, movedId: UUID, beforeId: UUID?) {
        var level = folders.filter { $0.parentId == parentId }.sorted { $0.sortOrder < $1.sortOrder }
        level.removeAll { $0.id == movedId }
        guard let moved = folders.first(where: { $0.id == movedId }) else { return }
        if let beforeId, let targetIdx = level.firstIndex(where: { $0.id == beforeId }) {
            level.insert(moved, at: targetIdx)
        } else {
            level.append(moved)
        }
        for (i, f) in level.enumerated() {
            if let idx = folders.firstIndex(where: { $0.id == f.id }) { folders[idx].sortOrder = i }
        }
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
            // Same one-time format-upgrade notice as manual credential edits.
            let wasLegacy = db.credentialStoreIsLegacy()
            try? db.saveCredentials(self.credentials, masterPassword: masterPassword)
            if wasLegacy { showCredentialFormatUpgradeNotice = true }
        }
    }

    // MARK: - CSV Import (Termius format, legacy)

    func importCSV(_ content: String) {
        let result = Self.parseImportCSV(content, existingFolders: folders)
        folders.append(contentsOf: result.newFolders)
        sessions.append(contentsOf: result.sessions)
        db.saveFolders(folders)
        db.saveSessions(sessions)
    }

    /// Pure parser: turns Termius-format CSV into sessions + any new folders, without
    /// touching the database. Extracted so it can be unit-tested in isolation.
    static func parseImportCSV(_ content: String, existingFolders: [Folder])
        -> (sessions: [Session], newFolders: [Folder]) {
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return ([], []) }

        var newSessions: [Session] = []
        var newFolders: [Folder] = []

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
                if let existing = (existingFolders + newFolders).first(where: { $0.name == groupName && $0.parentId == nil }) {
                    folderId = existing.id
                } else {
                    var folder = Folder()
                    folder.name = groupName
                    newFolders.append(folder)
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
            newSessions.append(s)
        }
        return (newSessions, newFolders)
    }

    private static func parseCSVLine(_ line: String) -> [String] {
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
