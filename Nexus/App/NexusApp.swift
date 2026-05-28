import SwiftUI

@main
struct NexusApp: App {
    @State private var appViewModel = AppViewModel()
    @State private var updaterViewModel = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appViewModel)
                .environment(updaterViewModel)
                // Explicit minimum prevents the window from shrinking when sheets
                // open/close as attached panels, which causes the "sliding" position drift.
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            NexusCommands(vm: appViewModel, updaterVM: updaterViewModel)
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(appViewModel)
                .environment(updaterViewModel)
        }
    }
}

// MARK: - Menu commands

struct NexusCommands: Commands {
    let vm: AppViewModel
    let updaterVM: UpdaterViewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("menu.new_session") {
                vm.addSessionParentFolderId = nil
                vm.showAddSession = true
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("menu.new_folder") {
                vm.addSessionParentFolderId = nil
                vm.showAddFolder = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("menu.import_csv") {
                vm.showImportCSV = true
            }
        }

        CommandGroup(after: .appInfo) {
            Button("menu.check_for_updates") {
                updaterVM.checkForUpdates()
            }
        }

        CommandGroup(replacing: .help) {
            Button("menu.password_manager") {
                vm.showPasswordManager = true
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}
