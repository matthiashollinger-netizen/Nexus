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
