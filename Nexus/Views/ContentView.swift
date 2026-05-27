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

    var body: some View {
        @Bindable var vm = vm
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            TerminalTabsView()
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
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
        .onAppear {
            setupMenu()
        }
    }

    private func setupMenu() {
        // Menu items are handled via commands in NexusApp
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
}
