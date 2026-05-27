import SwiftUI

@main
struct NexusApp: App {
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appViewModel)
        }
        .commands {
            NexusCommands(vm: appViewModel)
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsView()
                .environment(appViewModel)
        }
    }
}

// MARK: - Menu commands

struct NexusCommands: Commands {
    let vm: AppViewModel

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

        CommandGroup(replacing: .help) {
            Button("menu.password_manager") {
                vm.showPasswordManager = true
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}
