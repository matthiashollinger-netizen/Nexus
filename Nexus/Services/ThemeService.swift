import Foundation
import AppKit
import SwiftTerm

// MARK: - Theme Service

@Observable
final class ThemeService {
    static let shared = ThemeService()

    var themes: [NexusTheme] = []
    var activeThemeId: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var activeTheme: NexusTheme {
        themes.first { $0.id == activeThemeId } ?? .nexusDark
    }

    private var appSupportURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nexus")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var themesFileURL: URL {
        appSupportURL.appendingPathComponent("themes.json")
    }

    // MARK: - Load / Save

    func loadThemes() {
        var all = NexusTheme.allBuiltIn
        if let data = try? Data(contentsOf: themesFileURL),
           let custom = try? JSONDecoder().decode([NexusTheme].self, from: data) {
            all.append(contentsOf: custom)
        }
        themes = all
    }

    func saveThemes() {
        let custom = themes.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(custom) else { return }
        try? data.write(to: themesFileURL, options: .atomicWrite)
    }

    // MARK: - Apply

    func applyTheme(_ theme: NexusTheme) {
        activeThemeId = theme.id
    }

    // MARK: - Export / Import

    func exportTheme(_ theme: NexusTheme) throws -> URL {
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("\(theme.name.replacingOccurrences(of: " ", with: "_")).nexustheme")
        let data = try JSONEncoder().encode(theme)
        try data.write(to: url, options: .atomicWrite)
        return url
    }

    func importTheme(from url: URL) throws {
        let data = try Data(contentsOf: url)
        var theme = try JSONDecoder().decode(NexusTheme.self, from: data)
        theme.id = UUID()
        theme.isBuiltIn = false
        themes.append(theme)
        saveThemes()
    }

    // MARK: - Apply to terminal view

    func applyToTerminalView(_ view: TerminalView, theme: NexusTheme) {
        view.nativeBackgroundColor = theme.terminalBackground.nsColor
        view.nativeForegroundColor = theme.terminalForeground.nsColor
        // Convert CodableColor ANSI palette to SwiftTerm Color objects
        if theme.ansiColors.count >= 16 {
            let swiftTermColors: [SwiftTerm.Color] = theme.ansiColors.prefix(16).map { cc in
                SwiftTerm.Color(red: UInt16(cc.red * 65535),
                                green: UInt16(cc.green * 65535),
                                blue: UInt16(cc.blue * 65535))
            }
            view.installColors(swiftTermColors)
        }
    }
}
