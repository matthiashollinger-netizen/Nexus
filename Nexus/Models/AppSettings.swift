import Foundation

struct AppSettings: Codable {
    var language: String = {
        Locale.current.language.languageCode?.identifier == "de" ? "de" : "en"
    }()
    var sshLegacyAlgorithms: Bool = true
    var terminalFontName: String = "Menlo"
    var terminalFontSize: Double = 13.0
    var defaultSSHPort: Int = 22
    var defaultTelnetPort: Int = 23
    var masterPasswordEnabled: Bool = false
    var hasCompletedOnboarding: Bool = false

    // Editor
    var preferredEditorApp: String = "builtin"   // builtin/vscode/bbedit/custom

    // Syntax Highlighting
    var enabledHighlightRulesets: [String] = ["default"]

    // Theme
    var activeThemeId: String = "nexusDark"
}
