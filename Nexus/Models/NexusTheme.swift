import Foundation
import AppKit

// MARK: - Codable Color

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1.0

    var nsColor: NSColor {
        NSColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    static var defaultANSI16: [CodableColor] {
        [
            // Normal
            CodableColor(red: 0,    green: 0,    blue: 0),       // 0 Black
            CodableColor(red: 0.8,  green: 0.1,  blue: 0.1),     // 1 Red
            CodableColor(red: 0.1,  green: 0.7,  blue: 0.1),     // 2 Green
            CodableColor(red: 0.8,  green: 0.7,  blue: 0.1),     // 3 Yellow
            CodableColor(red: 0.1,  green: 0.3,  blue: 0.8),     // 4 Blue
            CodableColor(red: 0.7,  green: 0.1,  blue: 0.7),     // 5 Magenta
            CodableColor(red: 0.1,  green: 0.7,  blue: 0.7),     // 6 Cyan
            CodableColor(red: 0.75, green: 0.75, blue: 0.75),    // 7 White
            // Bright
            CodableColor(red: 0.4,  green: 0.4,  blue: 0.4),     // 8 Bright Black
            CodableColor(red: 1.0,  green: 0.3,  blue: 0.3),     // 9 Bright Red
            CodableColor(red: 0.3,  green: 1.0,  blue: 0.3),     // 10 Bright Green
            CodableColor(red: 1.0,  green: 1.0,  blue: 0.3),     // 11 Bright Yellow
            CodableColor(red: 0.3,  green: 0.5,  blue: 1.0),     // 12 Bright Blue
            CodableColor(red: 1.0,  green: 0.3,  blue: 1.0),     // 13 Bright Magenta
            CodableColor(red: 0.3,  green: 1.0,  blue: 1.0),     // 14 Bright Cyan
            CodableColor(red: 1.0,  green: 1.0,  blue: 1.0),     // 15 Bright White
        ]
    }
}

// MARK: - Nexus Theme

struct NexusTheme: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var isBuiltIn: Bool = false

    var terminalBackground: CodableColor = .init(red: 0,   green: 0,   blue: 0)
    var terminalForeground: CodableColor = .init(red: 0.8, green: 0.8, blue: 0.8)
    var terminalCursorColor: CodableColor = .init(red: 1,  green: 1,   blue: 1)
    var ansiColors: [CodableColor] = CodableColor.defaultANSI16

    var sidebarBackground: CodableColor = .init(red: 0.1, green: 0.1, blue: 0.1)
    var accentColor: CodableColor = .init(red: 0.2, green: 0.5, blue: 1.0)

    var terminalFont: String = "Menlo"
    var terminalFontSize: Double = 13.0

    var cursorStyle: CursorStyle = .block
    var cursorBlink: Bool = false
    var scrollbackLines: Int = 10000

    enum CursorStyle: String, Codable, CaseIterable {
        case block, underline, bar
        var displayName: String { rawValue.capitalized }
    }
}

// MARK: - Built-in Themes

extension NexusTheme {
    static var nexusDark: NexusTheme {
        var t = NexusTheme(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Nexus Dark")
        t.isBuiltIn = true
        return t
    }

    static var nexusLight: NexusTheme {
        var t = NexusTheme(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Nexus Light")
        t.isBuiltIn = true
        t.terminalBackground = .init(red: 0.96, green: 0.96, blue: 0.96)
        t.terminalForeground = .init(red: 0.1,  green: 0.1,  blue: 0.1)
        t.terminalCursorColor = .init(red: 0,   green: 0,    blue: 0)
        t.sidebarBackground = .init(red: 0.9,   green: 0.9,  blue: 0.9)
        return t
    }

    static var solarizedDark: NexusTheme {
        var t = NexusTheme(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Solarized Dark")
        t.isBuiltIn = true
        t.terminalBackground = .init(red: 0, green: 0.169, blue: 0.212)
        t.terminalForeground = .init(red: 0.514, green: 0.58, blue: 0.588)
        t.sidebarBackground  = .init(red: 0, green: 0.137, blue: 0.176)
        t.accentColor        = .init(red: 0.149, green: 0.545, blue: 0.824)
        return t
    }

    static var monokai: NexusTheme {
        var t = NexusTheme(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Monokai")
        t.isBuiltIn = true
        t.terminalBackground = .init(red: 0.157, green: 0.157, blue: 0.157)
        t.terminalForeground = .init(red: 0.972, green: 0.972, blue: 0.949)
        t.terminalCursorColor = .init(red: 0.972, green: 0.654, blue: 0.4)
        t.accentColor = .init(red: 0.972, green: 0.654, blue: 0.4)
        t.sidebarBackground = .init(red: 0.118, green: 0.118, blue: 0.118)
        return t
    }

    static var nord: NexusTheme {
        var t = NexusTheme(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "Nord")
        t.isBuiltIn = true
        t.terminalBackground = .init(red: 0.180, green: 0.204, blue: 0.251)
        t.terminalForeground = .init(red: 0.847, green: 0.871, blue: 0.914)
        t.sidebarBackground  = .init(red: 0.149, green: 0.169, blue: 0.208)
        t.accentColor        = .init(red: 0.533, green: 0.753, blue: 0.816)
        return t
    }

    static var dracula: NexusTheme {
        var t = NexusTheme(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!, name: "Dracula")
        t.isBuiltIn = true
        t.terminalBackground = .init(red: 0.157, green: 0.165, blue: 0.212)
        t.terminalForeground = .init(red: 0.973, green: 0.973, blue: 0.949)
        t.terminalCursorColor = .init(red: 0.741, green: 0.576, blue: 0.976)
        t.accentColor        = .init(red: 0.741, green: 0.576, blue: 0.976)
        t.sidebarBackground  = .init(red: 0.118, green: 0.125, blue: 0.165)
        return t
    }

    static var ciscoGreen: NexusTheme {
        var t = NexusTheme(id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!, name: "Cisco Green")
        t.isBuiltIn = true
        t.terminalBackground = .init(red: 0,    green: 0.06, blue: 0)
        t.terminalForeground = .init(red: 0,    green: 0.9,  blue: 0)
        t.terminalCursorColor = .init(red: 0,   green: 1,    blue: 0)
        t.sidebarBackground  = .init(red: 0,    green: 0.04, blue: 0)
        t.accentColor        = .init(red: 0,    green: 0.8,  blue: 0)
        return t
    }

    static var allBuiltIn: [NexusTheme] {
        [.nexusDark, .nexusLight, .solarizedDark, .monokai, .nord, .dracula, .ciscoGreen]
    }
}
