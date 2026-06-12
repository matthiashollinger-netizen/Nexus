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

    // Recently connected sessions (most-recent first, capped) — powers the
    // Dashboard "Recent" section and the Command Palette empty-query list.
    var recentSessionIds: [UUID] = []

    // Sidebar row density (compact = 28pt rows, comfortable = 32pt).
    var sidebarCompact: Bool = true

    // Notify (macOS UserNotifications) when a session disconnects/fails.
    var notifyOnDisconnect: Bool = true

    init() {}
}

// Tolerant decoder — see Session.swift for the rationale. New settings added later
// won't reset the whole settings object just because an old file lacks the key.
extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case language, sshLegacyAlgorithms, terminalFontName, terminalFontSize
        case defaultSSHPort, defaultTelnetPort, masterPasswordEnabled, hasCompletedOnboarding
        case preferredEditorApp, enabledHighlightRulesets, activeThemeId
        case recentSessionIds, sidebarCompact, notifyOnDisconnect
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        self.init()
        language                 = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        sshLegacyAlgorithms      = try c.decodeIfPresent(Bool.self, forKey: .sshLegacyAlgorithms) ?? d.sshLegacyAlgorithms
        terminalFontName         = try c.decodeIfPresent(String.self, forKey: .terminalFontName) ?? d.terminalFontName
        terminalFontSize         = try c.decodeIfPresent(Double.self, forKey: .terminalFontSize) ?? d.terminalFontSize
        defaultSSHPort           = try c.decodeIfPresent(Int.self, forKey: .defaultSSHPort) ?? d.defaultSSHPort
        defaultTelnetPort        = try c.decodeIfPresent(Int.self, forKey: .defaultTelnetPort) ?? d.defaultTelnetPort
        masterPasswordEnabled    = try c.decodeIfPresent(Bool.self, forKey: .masterPasswordEnabled) ?? d.masterPasswordEnabled
        hasCompletedOnboarding   = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        preferredEditorApp       = try c.decodeIfPresent(String.self, forKey: .preferredEditorApp) ?? d.preferredEditorApp
        enabledHighlightRulesets = try c.decodeIfPresent([String].self, forKey: .enabledHighlightRulesets) ?? d.enabledHighlightRulesets
        activeThemeId            = try c.decodeIfPresent(String.self, forKey: .activeThemeId) ?? d.activeThemeId
        recentSessionIds         = try c.decodeIfPresent([UUID].self, forKey: .recentSessionIds) ?? d.recentSessionIds
        sidebarCompact           = try c.decodeIfPresent(Bool.self, forKey: .sidebarCompact) ?? d.sidebarCompact
        notifyOnDisconnect       = try c.decodeIfPresent(Bool.self, forKey: .notifyOnDisconnect) ?? d.notifyOnDisconnect
    }
}
