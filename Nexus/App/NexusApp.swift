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
                // Keep the window min height ≥ the tallest attached sheet (AddSessionView
                // is 620). If the window can be shorter than the sheet, macOS grows it to
                // fit and the window visibly "slides down" — this floor prevents that.
                .frame(minWidth: 900, minHeight: 680)
                // nexus:// deep links (open/connect a session from a link).
                .onOpenURL { appViewModel.handleURL($0) }
        }
        .commands {
            NexusCommands(vm: appViewModel, updaterVM: updaterViewModel)
        }
        .defaultSize(width: 1100, height: 760)
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

        Window("editor.title", id: "editor") {
            NexusTextEditorView()
        }
        .defaultSize(width: 860, height: 600)
        .windowResizability(.contentMinSize)

        Window("macro.manager.title", id: "macros") {
            MacroManagerView()
                .environment(appViewModel)
        }
        .defaultSize(width: 700, height: 500)
        .windowResizability(.contentMinSize)

        Window("servers.title", id: "servers") {
            EmbeddedServersView()
        }
        .defaultSize(width: 720, height: 540)
        .windowResizability(.contentMinSize)

        Window("themes.title", id: "themes") {
            ThemeEditorView()
                .environment(appViewModel)
        }
        .defaultSize(width: 860, height: 600)
        .windowResizability(.contentMinSize)

        Window("toolbox.title", id: "toolbox") {
            NetworkToolboxView()
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

        CommandMenu("menu.macros") {
            MacroMenuItems()
        }

        CommandMenu("menu.tools") {
            ToolsMenuItems()
        }

        CommandGroup(after: .toolbar) {
            Button("menu.command_palette") {
                vm.showCommandPalette = true
            }
            .keyboardShortcut("k", modifiers: [.command])
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

// MARK: - Tools menu (View wrapper required for @Environment openWindow)

private struct ToolsMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("menu.server_manager") {
            openWindow(id: "servers")
        }
        .keyboardShortcut("s", modifiers: [.command, .shift, .option])

        Button("menu.toolbox") {
            openWindow(id: "toolbox")
        }
        .keyboardShortcut("t", modifiers: [.command, .shift, .option])

        Divider()

        Button("menu.theme_editor") {
            openWindow(id: "themes")
        }
        Button("menu.text_editor") {
            openWindow(id: "editor")
        }
    }
}

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
