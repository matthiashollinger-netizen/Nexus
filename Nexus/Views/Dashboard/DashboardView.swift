import SwiftUI

// MARK: - Dashboard / Home
//
// Replaces the old centered "Welcome" placeholder shown when no session is open.
// A greeting + quick-connect bar, quick-action grid, at-a-glance stats, recent &
// favorite connections, and live embedded-server status — a launchpad, not a
// dead screen. Rendered by TerminalTabsView only while `vm.activeSessions` is
// empty, so the working terminal path is never touched.

struct DashboardView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var greetingKey: LocalizedStringKey {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "dashboard.greeting.morning"
        case 12..<17: return "dashboard.greeting.afternoon"
        case 17..<22: return "dashboard.greeting.evening"
        default: return "dashboard.greeting.night"
        }
    }

    private var subtitleText: String {
        String(format: String(localized: "dashboard.subtitle"), vm.sessions.count, vm.folders.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                hero
                quickActions
                stats
                if !vm.favoriteSessions.isEmpty { favorites }
                recents
                servers
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(DS.Space.xxxl)
            .frame(maxWidth: .infinity)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .background(DS.Color.surface)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion { appeared = true }
            else { withAnimation(DS.Motion.gentle.delay(0.04)) { appeared = true } }
        }
    }

    // MARK: Hero + quick-connect

    private var hero: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("NEXUS")
                    .font(DS.Font.eyebrow).textCase(.uppercase).tracking(1.5)
                    .foregroundStyle(DS.Color.accent)
                Text(greetingKey)
                    .font(DS.Font.display)
                Text(subtitleText)
                    .font(DS.Font.callout)
                    .foregroundStyle(.secondary)
            }
            quickConnectBar
        }
    }

    private var quickConnectBar: some View {
        Button { vm.showCommandPalette = true } label: {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("dashboard.quickconnect.placeholder")
                    .font(DS.Font.body)
                    .foregroundStyle(.secondary)
                Spacer()
                KeyHint(["⌘", "K"])
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)
            .background(DS.Color.surfaceRaised, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Quick actions

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DS.Space.md)], spacing: DS.Space.md) {
            QuickActionTile(symbol: "plus.circle", title: "dashboard.action.new_session") {
                vm.addSessionParentFolderId = nil; vm.showAddSession = true
            }
            QuickActionTile(symbol: "folder.badge.plus", title: "dashboard.action.new_folder") {
                vm.addSessionParentFolderId = nil; vm.showAddFolder = true
            }
            QuickActionTile(symbol: "square.and.arrow.down", title: "dashboard.action.import") {
                vm.showImportCSV = true
            }
            QuickActionTile(symbol: "key.horizontal", title: "dashboard.action.passwords") {
                vm.showPasswordManager = true
            }
            QuickActionTile(symbol: "server.rack", title: "dashboard.action.servers") {
                openWindow(id: "servers")
            }
            QuickActionTile(symbol: "paintpalette", title: "dashboard.action.themes") {
                openWindow(id: "themes")
            }
        }
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: DS.Space.md) {
            statCard(value: vm.sessions.count, label: "dashboard.stat.sessions", symbol: "rectangle.stack")
            statCard(value: vm.folders.count, label: "dashboard.stat.folders", symbol: "folder")
            statCard(value: runningServerCount, label: "dashboard.stat.servers", symbol: "bolt.horizontal")
        }
    }

    private func statCard(value: Int, label: LocalizedStringKey, symbol: String) -> some View {
        NexusCard(hoverLift: false) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: symbol)
                    .font(.system(size: DS.Icon.card))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DS.Color.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(value)")
                        .font(DS.Font.display).monospacedDigit()
                    Text(label)
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Favorites

    private var favorites: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SectionHeader("dashboard.favorites", count: vm.favoriteSessions.count)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: DS.Space.md)], spacing: DS.Space.md) {
                ForEach(vm.favoriteSessions.prefix(6)) { session in
                    SessionMiniCard(session: session)
                }
            }
        }
    }

    // MARK: Recents

    private var recents: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SectionHeader("dashboard.recent", count: vm.recentSessions.isEmpty ? nil : vm.recentSessions.count)
            if vm.recentSessions.isEmpty {
                NexusCard(hoverLift: false) {
                    EmptyStateView(
                        symbol: "clock.arrow.circlepath",
                        title: "dashboard.recent.empty.title",
                        message: "dashboard.recent.empty.message",
                        primary: ("dashboard.action.new_session", {
                            vm.addSessionParentFolderId = nil; vm.showAddSession = true
                        })
                    )
                    .frame(minHeight: 180)
                }
            } else {
                VStack(spacing: DS.Space.xs) {
                    ForEach(vm.recentSessions.prefix(6)) { session in
                        RecentSessionRow(session: session)
                    }
                }
            }
        }
    }

    // MARK: Servers

    private var servers: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SectionHeader("dashboard.servers", actionLabel: "dashboard.servers.manage") {
                openWindow(id: "servers")
            }
            let running = EmbeddedServerService.shared.servers.filter { $0.isRunning }
            if running.isEmpty {
                InfoCard(style: .info, message: "dashboard.servers.idle")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: DS.Space.md)], spacing: DS.Space.md) {
                    ForEach(running) { server in
                        ServerMiniCard(server: server)
                    }
                }
            }
        }
    }

    private var runningServerCount: Int {
        EmbeddedServerService.shared.servers.filter { $0.isRunning }.count
    }
}

// MARK: - Recent session row

private struct RecentSessionRow: View {
    let session: Session
    @Environment(AppViewModel.self) private var vm
    @State private var hovering = false

    private var displayName: String { session.name.isEmpty ? session.host : session.name }

    var body: some View {
        Button { vm.connect(to: session) } label: {
            HStack(spacing: DS.Space.md) {
                Image(systemName: session.connectionType.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: DS.Icon.row)
                Text(displayName).font(DS.Font.body).lineLimit(1)
                if !session.host.isEmpty && session.host != displayName {
                    MonoText("\(session.host):\(session.port)")
                }
                Spacer()
                if let state = vm.liveState(for: session) {
                    StateBadge(state: state)
                } else if hovering {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "play.fill").font(.caption2)
                        Text("action.connect").font(DS.Font.caption)
                    }
                    .foregroundStyle(DS.Color.accent)
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)
            .background(hovering ? DS.Color.rowHover : .clear,
                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(DS.Motion.quick) { hovering = h } }
    }
}

// MARK: - Session mini card (favorites grid)

private struct SessionMiniCard: View {
    let session: Session
    @Environment(AppViewModel.self) private var vm

    private var displayName: String { session.name.isEmpty ? session.host : session.name }

    var body: some View {
        Button { vm.connect(to: session) } label: {
            NexusCard(padding: DS.Space.lg) {
                HStack(spacing: DS.Space.md) {
                    ZStack {
                        if let state = vm.liveState(for: session) {
                            StatusDot(state: state)
                        }
                    }
                    .frame(width: DS.Icon.statusDot)
                    Image(systemName: session.connectionType.systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(DS.Color.accent)
                        .frame(width: DS.Icon.row)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayName).font(DS.Font.body).lineLimit(1)
                        if !session.host.isEmpty {
                            MonoText("\(session.host):\(session.port)")
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(PlainButtonStyleNoHighlight())
    }
}

// MARK: - Server mini card (dashboard)

private struct ServerMiniCard: View {
    let server: EmbeddedServer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NexusCard(padding: DS.Space.lg, hoverLift: false) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: server.type.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DS.Color.accent)
                    .frame(width: DS.Icon.row)
                VStack(alignment: .leading, spacing: 1) {
                    Text(server.type.displayName).font(DS.Font.body)
                    MonoText(addressText)
                }
                Spacer(minLength: 0)
                StatusDot(state: server.isRunning ? .connected : .idle)
            }
        }
    }

    private var addressText: String {
        let ip = EmbeddedServerService.localIPAddress() ?? "127.0.0.1"
        return "\(ip):\(server.port)"
    }
}

/// A plain button that doesn't add its own pressed-state highlight (NexusCard
/// already provides hover feedback).
private struct PlainButtonStyleNoHighlight: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}
