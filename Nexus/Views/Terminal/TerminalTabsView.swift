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
    @Environment(AppViewModel.self) private var vm

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
                        .onTapGesture { vm.selectedTabId = cs.id }
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
        HStack(spacing: 6) {
            Image(systemName: cs.session.connectionType.systemImage)
                .font(.caption)
                .foregroundStyle(stateColor)
            Text(cs.tabTitle)
                .font(.system(size: 12))
                .lineLimit(1)
            Button {
                vm.closeSession(cs)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
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

struct TabContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        if let selected = vm.activeSessions.first(where: { $0.id == vm.selectedTabId }) {
            NexusTerminalView(
                cs: selected,
                fontName: vm.settings.terminalFontName,
                fontSize: vm.settings.terminalFontSize
            )
            .id(selected.id)
            .sheet(isPresented: Binding(
                get: { selected.shouldOfferCredentialSave },
                set: { selected.shouldOfferCredentialSave = $0 }
            )) {
                SaveCredentialsSheet(cs: selected)
                    .environment(vm)
            }
        } else {
            Color.black
        }
    }
}
