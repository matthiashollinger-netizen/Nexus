import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    private var shouldShowOnboarding: Bool {
        // Show once to users who haven't configured encryption yet
        !vm.settings.hasCompletedOnboarding && !vm.settings.masterPasswordEnabled
    }

    var body: some View {
        if shouldShowOnboarding {
            OnboardingView()
        } else if vm.settings.masterPasswordEnabled && !vm.isUnlocked {
            MasterPasswordView()
        } else {
            MainView()
        }
    }
}

struct MainView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var didAutoConnect = false

    private var activeSSHSession: ConnectionSession? {
        vm.activeSessions.first {
            $0.session.connectionType == .ssh
        }
    }

    private var showSFTP: Bool {
        vm.showSFTPBrowser && activeSSHSession != nil
    }

    var body: some View {
        @Bindable var vm = vm
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            HSplitView {
                if showSFTP, let cs = activeSSHSession {
                    SFTPBrowserView(cs: cs)
                        .frame(minWidth: 240, maxWidth: 320)
                }
                TerminalTabsView()
                    .frame(minWidth: 400, maxWidth: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    vm.showSFTPBrowser.toggle()
                } label: {
                    Label("toolbar.sftp_browser", systemImage: "folder.fill.badge.person.crop")
                }
                .disabled(activeSSHSession == nil)
                .help("toolbar.sftp_browser")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    vm.toggleMultiExec()
                } label: {
                    Label("toolbar.multiexec", systemImage: vm.multiExecMode
                          ? "dot.radiowaves.left.and.right" : "rectangle.on.rectangle")
                }
                .disabled(vm.activeSessions.isEmpty)
                .help("toolbar.multiexec")
                .tint(vm.multiExecMode ? DS.Color.stateConnecting : nil)
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    if let cs = vm.activeConnection {
                        let live = vm.sessions.first { $0.id == cs.session.id } ?? cs.session
                        if live.snippets.isEmpty {
                            Text("snippets.none")
                        } else {
                            ForEach(live.snippets) { snip in
                                Button(snip.title.isEmpty ? snip.command : snip.title) {
                                    vm.sendSnippet(snip, to: cs)
                                }
                            }
                        }
                        Divider()
                        Button("snippets.edit") { vm.editingSnippetsSession = live }
                    }
                } label: {
                    Label("toolbar.snippets", systemImage: "text.append")
                }
                .disabled(vm.activeConnection == nil)
                .help("toolbar.snippets")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    vm.showPasswordManager = true
                } label: {
                    Label("toolbar.password_manager", systemImage: "key.horizontal")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    vm.showImportCSV = true
                } label: {
                    Label("toolbar.import", systemImage: "square.and.arrow.down")
                }
            }
        }
        .sheet(isPresented: $vm.showPasswordManager) {
            PasswordManagerView()
                .environment(vm)
        }
        .sheet(isPresented: $vm.showBugReporter) {
            BugReportView()
                .environment(vm)
        }
        .sheet(isPresented: $vm.showFeatureRequest) {
            FeatureRequestView()
        }
        .sheet(item: $vm.editingSnippetsSession) { session in
            SnippetEditorView(session: session).environment(vm)
        }
        // nexus://connect links are confirmed before dialing — a crafted link must not
        // silently connect the user to an arbitrary (possibly internal) host.
        .confirmationDialog(
            "url.connect.confirm.title",
            isPresented: Binding(
                get: { vm.pendingURLConnect != nil },
                set: { if !$0 { vm.pendingURLConnect = nil } }
            ),
            presenting: vm.pendingURLConnect
        ) { session in
            Button("url.connect.confirm.action") {
                vm.connect(to: session)
                vm.pendingURLConnect = nil
            }
            Button("action.cancel", role: .cancel) { vm.pendingURLConnect = nil }
        } message: { session in
            Text(String(format: NSLocalizedString("url.connect.confirm.message", comment: ""),
                        "\(session.username.isEmpty ? "" : session.username + "@")\(session.host):\(session.port)"))
        }
        // ⌘K Command Palette — a floating overlay (not a sheet) so it hovers over
        // the whole split view, Spotlight-style.
        .overlay {
            if vm.showCommandPalette {
                CommandPaletteView(isPresented: $vm.showCommandPalette)
                    .environment(vm)
                    .zIndex(100)
            }
        }
        .focusedValue(\.macroExecutorVM, vm.activeSessions)
        .onAppear {
            // Auto-connect flagged sessions once, shortly after the UI is up.
            if !didAutoConnect {
                didAutoConnect = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    vm.connectAutoSessions()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
}
