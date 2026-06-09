import Testing
import Foundation
import AppKit
@testable import Nexus

/// Theme import/export is JSON-based (`.nexustheme`). These verify the round-trip
/// that export+import rely on, plus graceful handling of malformed theme files.
struct ThemeCodableTests {

    @Test func builtInThemesEncodeDecode() throws {
        for theme in NexusTheme.allBuiltIn {
            let data = try JSONEncoder().encode(theme)
            let back = try JSONDecoder().decode(NexusTheme.self, from: data)
            #expect(back.id == theme.id)
            #expect(back.name == theme.name)
            #expect(back.ansiColors.count == theme.ansiColors.count)
            #expect(back.terminalBackground == theme.terminalBackground)
        }
    }

    @Test func exportImportRoundTripPreservesColors() throws {
        var theme = NexusTheme(id: UUID(), name: "My Custom")
        theme.terminalBackground = CodableColor(red: 0.12, green: 0.34, blue: 0.56)
        theme.accentColor = CodableColor(red: 1, green: 0.5, blue: 0)
        theme.terminalFontSize = 15

        let data = try JSONEncoder().encode(theme)
        let back = try JSONDecoder().decode(NexusTheme.self, from: data)
        #expect(abs(back.terminalBackground.red - 0.12) < 0.0001)
        #expect(abs(back.accentColor.green - 0.5) < 0.0001)
        #expect(back.terminalFontSize == 15)
    }

    @Test func malformedThemeFileDoesNotCrash() {
        // A corrupt .nexustheme must fail to decode gracefully (throw, not crash).
        let garbage = Data("{ not a theme }".utf8)
        let decoded = try? JSONDecoder().decode(NexusTheme.self, from: garbage)
        #expect(decoded == nil)
    }

    @Test func defaultANSIPaletteHas16Colors() {
        #expect(CodableColor.defaultANSI16.count == 16)
    }

    @Test func codableColorNSColorConversion() {
        let c = CodableColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let ns = c.nsColor
        #expect(abs(ns.redComponent - 0.2) < 0.01)
        #expect(abs(ns.alphaComponent - 0.8) < 0.01)
    }
}
