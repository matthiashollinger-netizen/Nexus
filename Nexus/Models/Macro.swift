import Foundation

struct Macro: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String = ""
    var description: String = ""
    var commands: [String] = []
    var hotkey: MacroHotkey? = nil
    var schedule: MacroSchedule? = nil
    var applyToSessionIds: [UUID] = []  // empty = all sessions
    var delayBetweenCommands: Double = 0.3

    struct MacroHotkey: Codable, Hashable {
        var key: String = ""
        var modifiers: [String] = []

        var displayString: String {
            var parts: [String] = []
            if modifiers.contains("control") { parts.append("⌃") }
            if modifiers.contains("option")  { parts.append("⌥") }
            if modifiers.contains("shift")   { parts.append("⇧") }
            if modifiers.contains("command") { parts.append("⌘") }
            parts.append(key.uppercased())
            return parts.joined()
        }
    }

    struct MacroSchedule: Codable {
        var enabled: Bool = false
        var intervalMinutes: Int = 60
        var runOnConnect: Bool = false
    }
}
