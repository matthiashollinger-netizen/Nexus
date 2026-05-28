import SwiftUI

// MARK: - Tab bar + terminal area

struct TerminalTabsView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            if vm.activeSessions.isEmpty {
                WelcomeView()
            } else {
                TabBarView()
                Divider()
                TabContentView()
            }
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("nexus.welcome.title")
                .font(.title2)
                .fontWeight(.semibold)
            Text("nexus.welcome.subtitle")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

// MARK: - Tab bar

struct TabBarView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(vm.activeSessions) { cs in
                    TabItemView(cs: cs, isSelected: vm.selectedTabId == cs.id)
                }
            }
            .frame(height: 36)
        }
        .background(.bar)
    }
}

struct TabItemView: View {
    let cs: ConnectionSession
    let isSelected: Bool
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 0) {
            // ── Tab label — tapping switches to this tab ──────────────
            HStack(spacing: 6) {
                Image(systemName: cs.session.connectionType.systemImage)
                    .font(.caption)
                    .foregroundStyle(stateColor)
                Text(cs.tabTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 36)
            .contentShape(Rectangle())
            .onTapGesture {
                vm.selectedTabId = cs.id
                // Give keyboard focus to the now-active terminal.
                // asyncAfter(0.05) lets SwiftUI finish re-rendering before we set focus.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard let view = cs.terminalNSView else { return }
                    view.window?.makeFirstResponder(view)
                }
            }

            // ── Close button — separate hit area, never competes with tap ─
            Button {
                vm.closeSession(cs)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .padding(6)           // generous touch target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.trailing, 4)
        }
        .background(isSelected ? Color(nsColor: .controlBackgroundColor) : .clear)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .frame(height: 2)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    var stateColor: Color {
        switch cs.state {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }
}

// MARK: - Terminal content
// All terminals stay in the view hierarchy (ZStack with opacity). This keeps each
// SSH/Telnet/Serial connection alive when the user switches between tabs.

struct TabContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        ZStack {
            ForEach(vm.activeSessions) { cs in
                NexusTerminalView(
                    cs: cs,
                    fontName: vm.settings.terminalFontName,
                    fontSize: vm.settings.terminalFontSize
                )
                // Hidden tabs have zero opacity but their NSViews stay alive
                .opacity(cs.id == vm.selectedTabId ? 1 : 0)
                .allowsHitTesting(cs.id == vm.selectedTabId)
            }
        }
        .background(Color.black)
        // Single sheet for whichever session wants credential save
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
}
