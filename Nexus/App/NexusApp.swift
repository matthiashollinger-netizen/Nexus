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

        Window("help.title", id: "help") {
            HelpView()
        }
        .defaultSize(width: 860, height: 580)
        .windowResizability(.contentMinSize)

        Window("changelog.title", id: "changelog") {
            ChangelogView()
        }
        .defaultSize(width: 720, height: 500)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Menu commands

struct NexusCommands: Commands {
    let vm: AppViewModel
    let updaterVM: UpdaterViewModel

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            SidebarUndoButton()
        }

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
            HelpMenuItems()
            Divider()
            Button("menu.report_bug") {
                vm.showBugReporter = true
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Button("menu.feature_request") {
                vm.showFeatureRequest = true
            }
            Divider()
            Button("menu.password_manager") {
                vm.showPasswordManager = true
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Undo sidebar move (View wrapper required for @FocusedValue)

private struct SidebarUndoButton: View {
    @FocusedValue(\.sidebarUndoVM) private var undoVM

    var body: some View {
        Button("action.undo_move") {
            undoVM?.undoLastMove()
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(undoVM == nil)
    }
}

// MARK: - Help menu items (View wrapper required for @Environment openWindow)

private struct HelpMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("menu.nexus_help") {
            openWindow(id: "help")
        }
        .keyboardShortcut("?", modifiers: .command)

        Button("menu.changelog") {
            openWindow(id: "changelog")
        }
    }
}
