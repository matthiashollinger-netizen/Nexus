import SwiftUI

// MARK: - Tab bar + terminal area

struct TerminalTabsView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var findVisible = false
    @State private var findTerm = ""
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if vm.activeSessions.isEmpty {
                DashboardView()
            } else {
                TabBarView()
                Divider()
                ZStack(alignment: .top) {
                    TabContentView()
                    if findVisible {
                        FindBar(term: $findTerm, focused: $findFocused,
                                onNext: { _ = terminalFind(vm.activeConnection, term: findTerm, forward: true) },
                                onPrev: { _ = terminalFind(vm.activeConnection, term: findTerm, forward: false) },
                                onClose: closeFind)
                            .padding(DS.Space.sm)
                    }
                }
                if vm.multiExecMode { BroadcastBar() }
            }
        }
        // ⌘F find — a key equivalent fires before the terminal's own NSTextFinder.
        .background {
            Button("") { toggleFind() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        }
    }

    private func toggleFind() {
        guard !vm.activeSessions.isEmpty else { return }
        findVisible.toggle()
        if findVisible { findFocused = true } else { terminalClearSearch(vm.activeConnection) }
    }

    private func closeFind() {
        findVisible = false
        terminalClearSearch(vm.activeConnection)
    }
}

// MARK: - Find bar (⌘F)

private struct FindBar: View {
    @Binding var term: String
    @FocusState.Binding var focused: Bool
    let onNext: () -> Void
    let onPrev: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("find.placeholder", text: $term)
                .textFieldStyle(.plain)
                .focused($focused)
                .frame(width: 220)
                .onSubmit(onNext)
            Button(action: onPrev) { Image(systemName: "chevron.up") }.buttonStyle(.borderless)
            Button(action: onNext) { Image(systemName: "chevron.down") }.buttonStyle(.borderless)
            Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
        }
        .font(DS.Font.body)
        .padding(.horizontal, DS.Space.md).padding(.vertical, DS.Space.sm)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.Color.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - MultiExec broadcast bar

private struct BroadcastBar: View {
    @Environment(AppViewModel.self) private var vm
    @State private var command = ""

    private var targetCount: Int { vm.broadcastTargets.count }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(DS.Color.stateConnecting)
                Text(String(format: String(localized: "multiexec.banner"), targetCount))
                    .font(DS.Font.caption.weight(.semibold))
                    .foregroundStyle(DS.Color.stateConnecting)
                TextField("multiexec.placeholder", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Font.mono)
                    .onSubmit(send)
                Button("multiexec.send", action: send)
                    .buttonStyle(.borderedProminent)
                    .disabled(targetCount == 0 || command.isEmpty)
            }
            .padding(.horizontal, DS.Space.lg).padding(.vertical, DS.Space.sm)
            .background(DS.Color.stateConnecting.opacity(0.10))
        }
    }

    private func send() {
        guard !command.isEmpty, targetCount > 0 else { return }
        vm.broadcast(command)
        command = ""
    }
}

// MARK: - Tab bar (with DragGesture reorder, browser-style)

/// Tracks each tab's measured width so we can calculate drop positions.
private struct TabWidthKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct TabBarView: View {
    @Environment(AppViewModel.self) private var vm

    // Drag state
    @State private var draggingId: UUID?      = nil
    @State private var dragOffsetX: CGFloat   = 0
    @State private var dropIndex: Int?        = nil   // "insert before" index
    @State private var tabWidths: [UUID: CGFloat] = [:]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(vm.activeSessions.enumerated()), id: \.element.id) { idx, cs in

                    // ── Insertion indicator before this tab ──────────────────
                    if showIndicator(at: idx) {
                        insertionBar
                    }

                    TabItemView(cs: cs, isSelected: vm.selectedTabId == cs.id)
                        // Dragged tab floats above siblings
                        .zIndex(draggingId == cs.id ? 10 : 0)
                        // Dragged tab moves with cursor
                        .offset(x: draggingId == cs.id ? dragOffsetX : 0)
                        // Lifted look while dragging
                        .opacity(draggingId == cs.id ? 0.85 : 1)
                        .scaleEffect(
                            CGSize(width: 1, height: draggingId == cs.id ? 0.92 : 1),
                            anchor: .top
                        )
                        // Measure tab width for drop-position maths
                        .background(GeometryReader { geo in
                            Color.clear.preference(
                                key: TabWidthKey.self,
                                value: [cs.id: geo.size.width]
                            )
                        })
                        // DragGesture: only on the label portion via minimumDistance
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    withAnimation(.interactiveSpring(response: 0.18)) {
                                        draggingId = cs.id
                                        dragOffsetX = value.translation.width
                                        dropIndex = computeDropIndex(
                                            draggedId: cs.id,
                                            translationX: value.translation.width
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    if let toIdx = dropIndex {
                                        vm.moveTabToIndex(id: cs.id, toIndex: toIdx)
                                    }
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                        draggingId = nil
                                        dragOffsetX = 0
                                        dropIndex   = nil
                                    }
                                }
                        )
                }

                // ── Insertion indicator after the last tab ────────────────
                if showIndicator(at: vm.activeSessions.count) {
                    insertionBar
                }
            }
            .frame(height: 36)
        }
        .background(.bar)
        .onPreferenceChange(TabWidthKey.self) { tabWidths = $0 }
    }

    // MARK: - Helpers

    private var insertionBar: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: 22)
            .transition(.opacity.combined(with: .scale))
    }

    /// Returns true when the drop-indicator should appear before position `idx`.
    private func showIndicator(at idx: Int) -> Bool {
        guard let fromId = draggingId,
              let fromIdx = vm.activeSessions.firstIndex(where: { $0.id == fromId }),
              let dropIdx = dropIndex else { return false }
        // Don't show indicator if it would leave the tab in the same slot
        guard dropIdx != fromIdx, dropIdx != fromIdx + 1 else { return false }
        return dropIdx == idx
    }

    /// Calculates the "insert before" index based on the drag translation.
    private func computeDropIndex(draggedId: UUID, translationX: CGFloat) -> Int {
        guard let fromIdx = vm.activeSessions.firstIndex(where: { $0.id == draggedId }) else {
            return 0
        }
        let defaultW: CGFloat = 130
        // Cumulative midpoints of each tab (relative to tab bar origin)
        var midpoints: [CGFloat] = []
        var x: CGFloat = 0
        for cs in vm.activeSessions {
            let w = tabWidths[cs.id] ?? defaultW
            midpoints.append(x + w / 2)
            x += w
        }
        // Virtual centre of the dragged tab after the drag
        let originalCentre = midpoints.indices.contains(fromIdx) ? midpoints[fromIdx] : 0
        let newCentre = originalCentre + translationX

        // First tab whose midpoint is to the RIGHT of the dragged tab's new centre
        if let idx = midpoints.firstIndex(where: { $0 > newCentre }) {
            return idx
        }
        return vm.activeSessions.count   // drop at end
    }
}

// MARK: - Tab item

struct TabItemView: View {
    let cs: ConnectionSession
    let isSelected: Bool
    @Environment(AppViewModel.self) private var vm
    @State private var closeHover = false

    var body: some View {
        HStack(spacing: 0) {
            // ── MultiExec selection checkbox (only while broadcasting) ─────
            if vm.multiExecMode {
                Button { vm.toggleExecMembership(cs.id) } label: {
                    Image(systemName: vm.selectedExecTabs.contains(cs.id) ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(vm.selectedExecTabs.contains(cs.id) ? DS.Color.stateConnecting : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, DS.Space.sm)
                .help("multiexec.include")
            }
            // ── Label — tapping switches to this tab ──────────────────────
            HStack(spacing: DS.Space.sm) {
                StatusDot(state: cs.state, size: 7)
                Image(systemName: cs.session.connectionType.systemImage)
                    .font(.system(size: DS.Icon.tab))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text(cs.tabTitle)
                    .font(DS.Font.callout)
                    .foregroundStyle(isSelected ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.leading, DS.Space.lg)
            .padding(.trailing, DS.Space.sm)
            .frame(height: 36)
            .contentShape(Rectangle())
            .onTapGesture {
                vm.selectedTabId = cs.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard let view = cs.terminalNSView else { return }
                    view.window?.makeFirstResponder(view)
                }
            }

            // ── Close button — separate hit area, highlights on hover ─────
            Button {
                vm.closeSession(cs)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(closeHover ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(closeHover ? DS.Color.rowHover : .clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { h in withAnimation(DS.Motion.quick) { closeHover = h } }
            .padding(.trailing, DS.Space.sm)
        }
        .background(isSelected ? DS.Color.surfaceRaised : .clear)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .frame(height: 2)
                    .foregroundStyle(DS.Color.accent)
            }
        }
    }
}

// MARK: - Terminal content (ZStack keeps all NSViews alive)

struct TabContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        // Reading ThemeService.shared.activeTheme here makes SwiftUI subscribe to
        // theme changes — any theme switch triggers updateNSView on all terminals.
        let globalTheme = ThemeService.shared.activeTheme
        // Background uses the selected tab's (possibly per-session) theme.
        let selectedTheme = resolvedTheme(for: vm.activeSessions.first { $0.id == vm.selectedTabId }, global: globalTheme)
        let bgColor = Color(selectedTheme.terminalBackground.nsColor)

        ZStack {
            ForEach(vm.activeSessions) { cs in
                NexusTerminalView(
                    cs: cs,
                    fontName: vm.settings.terminalFontName,
                    fontSize: cs.session.terminalFontSize ?? vm.settings.terminalFontSize,
                    theme: resolvedTheme(for: cs, global: globalTheme)
                )
                .opacity(cs.id == vm.selectedTabId ? 1 : 0)
                .allowsHitTesting(cs.id == vm.selectedTabId)
            }

            // Reconnect overlay for active disconnected/failed session
            if let activeCs = vm.activeSessions.first(where: { $0.id == vm.selectedTabId }) {
                switch activeCs.state {
                case .disconnected, .failed:
                    ReconnectOverlayView(cs: activeCs)
                default:
                    EmptyView()
                }
            }
        }
        .background(bgColor)
        .sheet(isPresented: Binding(
            get: { vm.activeSessions.contains(where: { $0.shouldOfferCredentialSave }) },
            set: { presented in
                if !presented {
                    vm.activeSessions.first(where: { $0.shouldOfferCredentialSave })?
                        .shouldOfferCredentialSave = false
                }
            }
        )) {
            if let cs = vm.activeSessions.first(where: { $0.shouldOfferCredentialSave }) {
                SaveCredentialsSheet(cs: cs).environment(vm)
            }
        }
    }

    /// Resolves the theme for a session: per-session override if set, else global.
    private func resolvedTheme(for cs: ConnectionSession?, global: NexusTheme) -> NexusTheme {
        guard let id = cs?.session.themeId,
              let theme = ThemeService.shared.themes.first(where: { $0.id == id }) else {
            return global
        }
        return theme
    }
}

// MARK: - Reconnect overlay

struct ReconnectOverlayView: View {
    @Environment(AppViewModel.self) private var vm
    let cs: ConnectionSession
    @State private var keyMonitor: Any?

    private var statusMessage: String {
        if case .failed(let msg) = cs.state { return msg }
        return String(localized: "connection.terminated")
    }

    private var isFailed: Bool { if case .failed = cs.state { return true }; return false }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: DS.Space.lg) {
                Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "bolt.slash.fill")
                    .font(.system(size: DS.Icon.emptyState))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isFailed ? DS.Color.stateFailed : .secondary)
                Text(statusMessage)
                    .font(DS.Font.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                HStack(spacing: DS.Space.md) {
                    Button("action.close") { vm.closeSession(cs) }
                        .buttonStyle(.bordered)
                    Button("action.reconnect") { vm.reconnect(cs: cs) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                Text("connection.reconnect_hint")
                    .font(DS.Font.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(DS.Space.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Enter / Cmd+R → reconnect
            if event.keyCode == 15 || event.keyCode == 36 || event.keyCode == 76 {
                DispatchQueue.main.async { vm.reconnect(cs: cs) }
                return nil
            }
            // Escape → close the dead tab
            if event.keyCode == 53 {
                DispatchQueue.main.async { vm.closeSession(cs) }
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }
}
