import SwiftUI
import AppKit

// MARK: - Command Palette (⌘K)
//
// A Spotlight-grade fuzzy launcher over sessions, open tabs, folders and app
// actions. Type three letters, hit ⏎, connect — no mouse. The search field is a
// thin NSTextField wrapper so ↑/↓/⏎/esc route to the model BEFORE the field's
// own cursor handling (pure SwiftUI .onKeyPress is swallowed by a focused
// TextField for arrow keys). The model is plain @Observable → unit-testable.

// MARK: Result model

enum PaletteGroup: Int {
    case openTabs, sessions, folders, actions
    var titleKey: LocalizedStringKey {
        switch self {
        case .openTabs: return "palette.group.tabs"
        case .sessions: return "palette.group.sessions"
        case .folders: return "palette.group.folders"
        case .actions: return "palette.group.actions"
        }
    }
}

struct PaletteResult: Identifiable {
    let id: String
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var shortcut: [String]? = nil
    var state: ConnectionState? = nil
    let group: PaletteGroup
    let run: () -> Void
}

// MARK: Fuzzy matcher
//
// Subsequence match with bonuses for consecutive runs, word-boundary / prefix
// starts and shorter targets. Returns the score plus the matched character
// indices (for live bolding). nil = no match.
func fuzzyMatch(_ query: String, _ text: String) -> (score: Int, indices: [Int])? {
    if query.isEmpty { return (0, []) }
    let q = Array(query.lowercased())
    let t = Array(text.lowercased())
    guard !t.isEmpty else { return nil }

    var qi = 0
    var indices: [Int] = []
    var score = 0
    var lastMatch = -2
    var consecutive = 0

    for (ti, ch) in t.enumerated() where qi < q.count && ch == q[qi] {
        indices.append(ti)
        if ti == lastMatch + 1 {
            consecutive += 1
            score += 6 + consecutive * 2
        } else {
            consecutive = 0
        }
        if ti == 0 {
            score += 12
        } else {
            let prev = t[ti - 1]
            if !prev.isLetter && !prev.isNumber { score += 9 }   // word boundary
        }
        score += 1
        lastMatch = ti
        qi += 1
    }

    guard qi == q.count else { return nil }
    score += max(0, 18 - t.count / 4)   // prefer shorter targets
    return (score, indices)
}

// MARK: Palette model

@Observable
final class PaletteModel {
    var query: String = ""
    var results: [PaletteResult] = []
    var selectedIndex: Int = 0

    private weak var vm: AppViewModel?
    private var openWindowHandler: (String) -> Void = { _ in }

    func configure(vm: AppViewModel, openWindow: @escaping (String) -> Void) {
        self.vm = vm
        self.openWindowHandler = openWindow
    }

    func reset() {
        query = ""
        rebuild()
    }

    func setQuery(_ q: String) {
        query = q
        rebuild()
    }

    func moveUp() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + results.count) % results.count
    }

    func moveDown() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % results.count
    }

    /// Runs the highlighted result. Returns true if the palette should dismiss.
    func runSelected(stay: Bool) -> Bool {
        guard results.indices.contains(selectedIndex) else { return true }
        results[selectedIndex].run()
        return !stay
    }

    func run(_ result: PaletteResult) {
        result.run()
    }

    // MARK: Build

    func rebuild() {
        guard let vm else { results = []; return }
        let q = query.trimmingCharacters(in: .whitespaces)
        var buckets: [PaletteGroup: [(PaletteResult, Int)]] = [:]
        func add(_ r: PaletteResult, _ score: Int) { buckets[r.group, default: []].append((r, score)) }

        // Open tabs
        for cs in vm.activeSessions {
            let sub = cs.session.host
            if let s = bestScore(q, primary: cs.title, hay: "\(cs.title) \(sub)") {
                add(PaletteResult(id: "tab-\(cs.id)", symbol: cs.session.connectionType.systemImage,
                                  title: cs.title, subtitle: sub.isEmpty ? nil : sub,
                                  state: cs.state, group: .openTabs,
                                  run: { [weak vm] in vm?.selectedTabId = cs.id }), s)
            }
        }

        // Sessions — empty query shows recents; otherwise the full list, fuzzy-ranked.
        let pool = q.isEmpty ? vm.recentSessions : vm.sessions
        for sess in pool {
            let title = sess.name.isEmpty ? sess.host : sess.name
            let sub = sess.host.isEmpty ? nil : "\(sess.host):\(sess.port)"
            let hay = "\(title) \(sess.host) \(sess.username) \(sess.tags.joined(separator: " "))"
            if let s = bestScore(q, primary: title, hay: hay) {
                add(PaletteResult(id: "sess-\(sess.id)", symbol: sess.connectionType.systemImage,
                                  title: title, subtitle: sub, state: vm.liveState(for: sess),
                                  group: .sessions,
                                  run: { [weak vm] in vm?.connect(to: sess) }), s)
            }
        }

        // Folders — only when searching.
        if !q.isEmpty {
            for folder in vm.folders {
                if let s = bestScore(q, primary: folder.name, hay: folder.name) {
                    add(PaletteResult(id: "fold-\(folder.id)", symbol: "folder", title: folder.name,
                                      group: .folders,
                                      run: { [weak self] in self?.reveal(folder) }), s)
                }
            }
        }

        // Actions
        for action in actionResults() {
            if let s = bestScore(q, primary: action.title, hay: action.title) {
                add(action, s)
            }
        }

        // Group order: empty query → tabs, recents, actions. Searching → sessions,
        // tabs, folders, actions (matches typical "what am I looking for" intent).
        let order: [PaletteGroup] = q.isEmpty
            ? [.openTabs, .sessions, .actions]
            : [.sessions, .openTabs, .folders, .actions]

        let caps: [PaletteGroup: Int] = [.sessions: q.isEmpty ? 6 : 8, .openTabs: 6, .folders: 6, .actions: 12]
        var flat: [PaletteResult] = []
        for group in order {
            let items = (buckets[group] ?? []).sorted { $0.1 > $1.1 }.map(\.0)
            flat.append(contentsOf: items.prefix(caps[group] ?? 8))
        }
        results = flat
        selectedIndex = 0
    }

    private func bestScore(_ q: String, primary: String, hay: String) -> Int? {
        if q.isEmpty { return 0 }
        let scores = [fuzzyMatch(q, primary)?.score, fuzzyMatch(q, hay)?.score].compactMap { $0 }
        return scores.max()
    }

    private func reveal(_ folder: Folder) {
        guard let vm else { return }
        var f = folder; f.isExpanded = true; vm.updateFolder(f)
        vm.selectedSidebarItems = [.folder(folder)]
    }

    private func actionResults() -> [PaletteResult] {
        guard let vm else { return [] }
        let ow = openWindowHandler
        return [
            PaletteResult(id: "act-new-session", symbol: "plus.circle",
                          title: String(localized: "palette.action.new_session"),
                          shortcut: ["⌘", "N"], group: .actions,
                          run: { [weak vm] in vm?.addSessionParentFolderId = nil; vm?.showAddSession = true }),
            PaletteResult(id: "act-new-folder", symbol: "folder.badge.plus",
                          title: String(localized: "palette.action.new_folder"),
                          shortcut: ["⌘", "⇧", "N"], group: .actions,
                          run: { [weak vm] in vm?.addSessionParentFolderId = nil; vm?.showAddFolder = true }),
            PaletteResult(id: "act-import", symbol: "square.and.arrow.down",
                          title: String(localized: "palette.action.import"), group: .actions,
                          run: { [weak vm] in vm?.showImportCSV = true }),
            PaletteResult(id: "act-pw", symbol: "key.horizontal",
                          title: String(localized: "palette.action.passwords"),
                          shortcut: ["⌘", "⇧", "K"], group: .actions,
                          run: { [weak vm] in vm?.showPasswordManager = true }),
            PaletteResult(id: "act-servers", symbol: "server.rack",
                          title: String(localized: "palette.action.servers"), group: .actions,
                          run: { ow("servers") }),
            PaletteResult(id: "act-themes", symbol: "paintpalette",
                          title: String(localized: "palette.action.themes"), group: .actions,
                          run: { ow("themes") }),
            PaletteResult(id: "act-editor", symbol: "doc.text",
                          title: String(localized: "palette.action.editor"), group: .actions,
                          run: { ow("editor") }),
            PaletteResult(id: "act-macros", symbol: "wand.and.stars",
                          title: String(localized: "palette.action.macros"), group: .actions,
                          run: { ow("macros") }),
            PaletteResult(id: "act-help", symbol: "questionmark.circle",
                          title: String(localized: "palette.action.help"), group: .actions,
                          run: { ow("help") }),
        ]
    }
}

// MARK: - Palette view

struct CommandPaletteView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool

    @State private var model = PaletteModel()
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .top) {
            // Escape-to-close. A `.cancelAction` key equivalent fires via
            // performKeyEquivalent BEFORE the focused NSTextField's field editor can
            // swallow Escape — the field editor only forwards navigation commands
            // (arrows/return) through its delegate, never cancelOperation.
            Button("") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            // Dimmed, tap-to-dismiss scrim.
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            card
                .frame(width: 620)
                .scaleEffect(shown ? 1 : 0.96)
                .opacity(shown ? 1 : 0)
                .padding(.top, 110)
        }
        .onAppear {
            model.configure(vm: vm) { id in openWindow(id: id) }
            model.reset()
            if reduceMotion { shown = true }
            else { withAnimation(DS.Motion.snappy) { shown = true } }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: DS.Space.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                PaletteTextField(
                    text: Binding(get: { model.query }, set: { model.setQuery($0) }),
                    onMoveUp: { model.moveUp() },
                    onMoveDown: { model.moveDown() },
                    onSubmit: { stay in if model.runSelected(stay: stay) { dismiss() } },
                    onCancel: { dismiss() }
                )
                .frame(height: 26)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)

            Divider()

            // Results
            if model.results.isEmpty {
                emptyResults
            } else {
                resultsList
            }

            Divider()
            footer
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(DS.Color.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                        if index == 0 || model.results[index - 1].group != result.group {
                            SectionHeader(result.group.titleKey)
                                .padding(.horizontal, DS.Space.lg)
                                .padding(.top, index == 0 ? DS.Space.md : DS.Space.lg)
                                .padding(.bottom, DS.Space.xs)
                        }
                        PaletteResultRow(result: result, isHighlighted: index == model.selectedIndex,
                                         query: model.query)
                            // Identify each row by its RESULT id (matching the ForEach's
                            // \.element.id). Using the positional index here pinned rows
                            // by slot and left reused rows showing a previous result's
                            // content while the count tracked the query.
                            .id(result.id)
                            .onTapGesture {
                                model.selectedIndex = index
                                model.run(result); dismiss()
                            }
                            .onHover { if $0 { model.selectedIndex = index } }
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }
            .frame(maxHeight: 380)
            .onChange(of: model.selectedIndex) { _, idx in
                guard model.results.indices.contains(idx) else { return }
                withAnimation(DS.Motion.quick) { proxy.scrollTo(model.results[idx].id, anchor: .center) }
            }
        }
    }

    private var emptyResults: some View {
        VStack(spacing: DS.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("palette.no_results")
                .font(DS.Font.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xxxl)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.lg) {
            footerHint(["↑", "↓"], "palette.footer.navigate")
            footerHint(["⏎"], "palette.footer.open")
            footerHint(["⌥", "⏎"], "palette.footer.stay")
            Spacer()
            footerHint(["esc"], "palette.footer.close")
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
    }

    private func footerHint(_ keys: [String], _ label: LocalizedStringKey) -> some View {
        HStack(spacing: DS.Space.xs) {
            KeyHint(keys)
            Text(label).font(DS.Font.caption).foregroundStyle(.tertiary)
        }
    }

    private func dismiss() {
        if reduceMotion { isPresented = false; return }
        withAnimation(DS.Motion.quick) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { isPresented = false }
    }
}

// MARK: - Result row

struct PaletteResultRow: View {
    let result: PaletteResult
    let isHighlighted: Bool
    let query: String

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: result.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isHighlighted ? DS.Color.accent : .secondary)
                .frame(width: DS.Icon.row)
            VStack(alignment: .leading, spacing: 1) {
                HighlightedText(text: result.title, query: query)
                    .font(DS.Font.body)
                if let subtitle = result.subtitle {
                    MonoText(subtitle)
                }
            }
            Spacer(minLength: DS.Space.sm)
            if let state = result.state {
                StatusDot(state: state)
            }
            if let shortcut = result.shortcut {
                KeyHint(shortcut)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(isHighlighted ? DS.Color.rowSelected : .clear,
                    in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .padding(.horizontal, DS.Space.sm)
        .contentShape(Rectangle())
    }
}

// MARK: - Live-bolding text

struct HighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        Text(attributed)
            .lineLimit(1)
    }

    private var attributed: AttributedString {
        let matched = Set(fuzzyMatch(query, text)?.indices ?? [])
        guard !matched.isEmpty else { return AttributedString(text) }
        var result = AttributedString()
        for (i, ch) in text.enumerated() {
            var piece = AttributedString(String(ch))
            if matched.contains(i) {
                piece.foregroundColor = DS.Color.accent
                piece.inlinePresentationIntent = .stronglyEmphasized
            }
            result.append(piece)
        }
        return result
    }
}

// MARK: - NSTextField wrapper (reliable arrow/return/escape routing)

struct PaletteTextField: NSViewRepresentable {
    @Binding var text: String
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onSubmit: (Bool) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = String(localized: "palette.placeholder")
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Refresh the coordinator's captured callbacks every update. Without this the
        // coordinator keeps the closures from makeCoordinator() — so onCancel()/onSubmit()
        // run against a stale view snapshot and their @State mutations never propagate
        // (this is why Escape didn't dismiss while the arrow keys, which mutate the
        // reference-typed model, did).
        context.coordinator.parent = self
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteTextField
        init(_ parent: PaletteTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp(); return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown(); return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(false); return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit(true); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel(); return true
            default:
                return false
            }
        }
    }
}
