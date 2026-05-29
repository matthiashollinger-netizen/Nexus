import Testing
@testable import Nexus
import Foundation

@MainActor
struct MacroTests {

    // MARK: - Save and Reload

    @Test func saveMacroAndReload() async throws {
        let service = MacroService.shared

        // Clear existing and save a known macro
        let originalMacros = service.macros
        defer {
            service.macros = originalMacros
            service.saveMacros()
        }

        var testMacro = Macro()
        testMacro.name = "Test Macro"
        testMacro.description = "A test macro"
        testMacro.commands = ["show version", "show interfaces", "exit"]
        testMacro.delayBetweenCommands = 0.5

        service.macros = [testMacro]
        service.saveMacros()

        // Reload
        let freshService = MacroService.shared
        freshService.loadMacros()

        let loaded = freshService.macros.first { $0.id == testMacro.id }
        #expect(loaded != nil)
        #expect(loaded?.name == "Test Macro")
        #expect(loaded?.commands.count == 3)
        #expect(loaded?.commands.first == "show version")
        #expect(loaded?.delayBetweenCommands == 0.5)
    }

    @Test func saveMacroWithHotkey() async throws {
        let service = MacroService.shared
        let originalMacros = service.macros
        defer {
            service.macros = originalMacros
            service.saveMacros()
        }

        var testMacro = Macro()
        testMacro.name = "Hotkey Macro"
        testMacro.hotkey = Macro.MacroHotkey(key: "h", modifiers: ["command", "shift"])

        service.macros = [testMacro]
        service.saveMacros()
        service.loadMacros()

        let loaded = service.macros.first { $0.id == testMacro.id }
        #expect(loaded?.hotkey?.key == "h")
        #expect(loaded?.hotkey?.modifiers.contains("command") == true)
        #expect(loaded?.hotkey?.modifiers.contains("shift") == true)
    }

    // MARK: - Schedule Parsing

    @Test func macroScheduleParsing() {
        var macro = Macro()
        macro.name = "Scheduled"
        macro.schedule = Macro.MacroSchedule(enabled: true, intervalMinutes: 30, runOnConnect: true)

        #expect(macro.schedule?.enabled == true)
        #expect(macro.schedule?.intervalMinutes == 30)
        #expect(macro.schedule?.runOnConnect == true)
    }

    @Test func macroScheduleDisabled() {
        var macro = Macro()
        macro.schedule = Macro.MacroSchedule(enabled: false, intervalMinutes: 60, runOnConnect: false)

        #expect(macro.schedule?.enabled == false)
        #expect(macro.schedule?.intervalMinutes == 60)
    }

    @Test func macroHotkeyDisplayString() {
        let hk = Macro.MacroHotkey(key: "t", modifiers: ["command", "shift"])
        let display = hk.displayString
        #expect(display.contains("⌘"))
        #expect(display.contains("⇧"))
        #expect(display.contains("T"))
    }

    @Test func macroHotkeyDisplayStringCtrlOpt() {
        let hk = Macro.MacroHotkey(key: "x", modifiers: ["control", "option"])
        let display = hk.displayString
        #expect(display.contains("⌃"))
        #expect(display.contains("⌥"))
    }

    @Test func macroApplyToSpecificSessions() {
        var macro = Macro()
        let sessionId1 = UUID()
        let sessionId2 = UUID()
        macro.applyToSessionIds = [sessionId1, sessionId2]

        #expect(macro.applyToSessionIds.count == 2)
        #expect(macro.applyToSessionIds.contains(sessionId1))
        #expect(macro.applyToSessionIds.contains(sessionId2))
    }

    @Test func macroApplyToAllSessions() {
        var macro = Macro()
        macro.applyToSessionIds = []  // empty = all sessions
        #expect(macro.applyToSessionIds.isEmpty)
    }

    @Test func macroCodableRoundTrip() throws {
        var macro = Macro()
        macro.name = "Codable Test"
        macro.description = "Testing JSON encoding"
        macro.commands = ["ping 8.8.8.8", "traceroute 1.1.1.1"]
        macro.hotkey = Macro.MacroHotkey(key: "p", modifiers: ["command"])
        macro.schedule = Macro.MacroSchedule(enabled: true, intervalMinutes: 15, runOnConnect: false)

        let encoded = try JSONEncoder().encode(macro)
        let decoded = try JSONDecoder().decode(Macro.self, from: encoded)

        #expect(decoded.name == macro.name)
        #expect(decoded.description == macro.description)
        #expect(decoded.commands == macro.commands)
        #expect(decoded.hotkey?.key == "p")
        #expect(decoded.schedule?.intervalMinutes == 15)
    }
}
