import Foundation
import AppKit

// MARK: - Macro Service

@Observable
final class MacroService {
    static let shared = MacroService()

    var macros: [Macro] = []

    private var scheduleTimers: [UUID: Timer] = [:]
    private var hotkeyMonitor: Any? = nil

    private var appSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent("Nexus")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var macrosFileURL: URL {
        appSupportURL.appendingPathComponent("macros.json")
    }

    // MARK: - Load / Save

    func loadMacros() {
        guard let data = try? Data(contentsOf: macrosFileURL),
              let decoded = try? JSONDecoder().decode([Macro].self, from: data) else { return }
        macros = decoded
    }

    func saveMacros() {
        guard let data = try? JSONEncoder().encode(macros) else { return }
        try? data.write(to: macrosFileURL, options: .atomicWrite)
    }

    // MARK: - Execute

    func executeMacro(_ macro: Macro, in sessions: [ConnectionSession]) {
        let targets: [ConnectionSession]
        if macro.applyToSessionIds.isEmpty {
            targets = sessions
        } else {
            targets = sessions.filter { macro.applyToSessionIds.contains($0.session.id) }
        }

        for session in targets {
            sendCommands(macro.commands, delay: macro.delayBetweenCommands, to: session)
        }
    }

    private func sendCommands(_ commands: [String], delay: Double, to session: ConnectionSession) {
        for (index, command) in commands.enumerated() {
            let dispatchTime = DispatchTime.now() + delay * Double(index)
            DispatchQueue.main.asyncAfter(deadline: dispatchTime) { [weak session] in
                guard let session else { return }
                let bytes = Array((command + "\n").utf8)
                session.terminalSendHandler?(bytes)
            }
        }
    }

    // MARK: - Scheduling

    func scheduleAllMacros(activeSessions: [ConnectionSession]) {
        stopAllSchedules()
        for macro in macros {
            guard let schedule = macro.schedule, schedule.enabled, schedule.intervalMinutes > 0 else { continue }
            let interval = TimeInterval(schedule.intervalMinutes * 60)
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.executeMacro(macro, in: activeSessions)
            }
            scheduleTimers[macro.id] = timer
        }
    }

    func stopAllSchedules() {
        scheduleTimers.values.forEach { $0.invalidate() }
        scheduleTimers.removeAll()
    }

    func runOnConnectMacros(for session: ConnectionSession) {
        for macro in macros {
            guard let schedule = macro.schedule, schedule.runOnConnect else { continue }
            let targets: [UUID] = macro.applyToSessionIds
            if targets.isEmpty || targets.contains(session.session.id) {
                sendCommands(macro.commands, delay: macro.delayBetweenCommands, to: session)
            }
        }
    }

    // MARK: - Hotkey Registration

    func installHotkeyMonitor(activeSessions: @escaping () -> [ConnectionSession]) {
        if let existing = hotkeyMonitor { NSEvent.removeMonitor(existing) }
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            for macro in self.macros {
                guard let hk = macro.hotkey, !hk.key.isEmpty else { continue }
                if self.eventMatchesHotkey(event, hotkey: hk) {
                    self.executeMacro(macro, in: activeSessions())
                    return nil // consume event
                }
            }
            return event
        }
    }

    func removeHotkeyMonitor() {
        if let m = hotkeyMonitor { NSEvent.removeMonitor(m) }
        hotkeyMonitor = nil
    }

    private func eventMatchesHotkey(_ event: NSEvent, hotkey: Macro.MacroHotkey) -> Bool {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard chars == hotkey.key.lowercased() else { return false }
        let mods = event.modifierFlags
        let needsCmd = hotkey.modifiers.contains("command")
        let needsShift = hotkey.modifiers.contains("shift")
        let needsOpt = hotkey.modifiers.contains("option")
        let needsCtrl = hotkey.modifiers.contains("control")
        return mods.contains(.command) == needsCmd
            && mods.contains(.shift) == needsShift
            && mods.contains(.option) == needsOpt
            && mods.contains(.control) == needsCtrl
    }
}
