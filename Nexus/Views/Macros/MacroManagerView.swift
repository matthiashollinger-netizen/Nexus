import SwiftUI
import AppKit

// MARK: - Macro Manager Window

struct MacroManagerView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var macroService = MacroService.shared
    @State private var selectedMacroId: UUID? = nil
    @State private var recordingHotkey = false
    @State private var hotkeyMonitor: Any? = nil

    private var selectedMacro: Binding<Macro>? {
        guard let id = selectedMacroId,
              let idx = macroService.macros.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.macroService.macros[idx] },
            set: { self.macroService.macros[idx] = $0; self.macroService.saveMacros() }
        )
    }

    var body: some View {
        HSplitView {
            // Left: Macro list
            VStack(spacing: 0) {
                List(macroService.macros, selection: $selectedMacroId) { macro in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(macro.name.isEmpty ? String(localized: "macro.new") : macro.name)
                                .fontWeight(.medium)
                            if let hk = macro.hotkey, !hk.key.isEmpty {
                                Text(hk.displayString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let schedule = macro.schedule, schedule.enabled {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(macro.id)
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button {
                        addMacro()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("macro.new")

                    Button {
                        deleteMacro()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedMacroId == nil)
                    .help("action.delete")

                    Spacer()

                    if selectedMacroId != nil {
                        Button {
                            if let macro = macroService.macros.first(where: { $0.id == selectedMacroId }) {
                                macroService.executeMacro(macro, in: vm.activeSessions)
                            }
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("macro.execute")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(minWidth: 180, maxWidth: 240)

            // Right: Editor
            if let binding = selectedMacro {
                MacroEditorView(
                    macro: binding,
                    activeSessions: vm.activeSessions,
                    recordingHotkey: $recordingHotkey,
                    onRecordHotkey: { startRecordingHotkey(binding: binding) }
                )
            } else {
                VStack {
                    Spacer()
                    Text("macro.select_hint")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .onAppear { macroService.loadMacros() }
        .onDisappear { stopRecordingHotkey() }
    }

    private func addMacro() {
        var macro = Macro()
        macro.name = String(localized: "macro.new")
        macroService.macros.append(macro)
        macroService.saveMacros()
        selectedMacroId = macro.id
    }

    private func deleteMacro() {
        guard let id = selectedMacroId else { return }
        macroService.macros.removeAll { $0.id == id }
        macroService.saveMacros()
        selectedMacroId = macroService.macros.first?.id
    }

    private func startRecordingHotkey(binding: Binding<Macro>) {
        recordingHotkey = true
        stopRecordingHotkey()
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard self.recordingHotkey else { return event }
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            var mods: [String] = []
            if event.modifierFlags.contains(.command) { mods.append("command") }
            if event.modifierFlags.contains(.shift)   { mods.append("shift") }
            if event.modifierFlags.contains(.option)  { mods.append("option") }
            if event.modifierFlags.contains(.control) { mods.append("control") }
            DispatchQueue.main.async {
                binding.hotkey.wrappedValue = Macro.MacroHotkey(key: key, modifiers: mods)
                self.recordingHotkey = false
            }
            return nil
        }
    }

    private func stopRecordingHotkey() {
        if let m = hotkeyMonitor { NSEvent.removeMonitor(m) }
        hotkeyMonitor = nil
        recordingHotkey = false
    }
}

// MARK: - Macro Editor

struct MacroEditorView: View {
    @Binding var macro: Macro
    let activeSessions: [ConnectionSession]
    @Binding var recordingHotkey: Bool
    let onRecordHotkey: () -> Void

    @State private var commandsText: String = ""

    var body: some View {
        Form {
            Section("session.general") {
                LabeledContent("macro.name") {
                    TextField("macro.name", text: $macro.name)
                }
                LabeledContent("macro.description") {
                    TextField("macro.description", text: $macro.description)
                }
            }

            Section("macro.commands") {
                TextEditor(text: $commandsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .onChange(of: commandsText) { _, new in
                        macro.commands = new.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                    }

                LabeledContent("macro.delay") {
                    HStack {
                        Slider(value: $macro.delayBetweenCommands, in: 0...5, step: 0.1)
                            .frame(width: 180)
                        Text(String(format: "%.1f s", macro.delayBetweenCommands))
                            .frame(width: 45)
                    }
                }
            }

            Section("macro.hotkey") {
                HStack {
                    if let hk = macro.hotkey, !hk.key.isEmpty {
                        Text(hk.displayString)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text("–")
                            .foregroundStyle(.secondary)
                    }

                    Button(recordingHotkey ? String(localized: "macro.hotkey.record") + "…" : String(localized: "macro.hotkey.record")) {
                        onRecordHotkey()
                    }
                    .buttonStyle(.bordered)

                    if macro.hotkey != nil {
                        Button("macro.hotkey.clear") {
                            macro.hotkey = nil
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
            }

            Section("macro.schedule") {
                Toggle("macro.schedule.enabled", isOn: Binding(
                    get: { macro.schedule?.enabled ?? false },
                    set: {
                        if macro.schedule == nil { macro.schedule = Macro.MacroSchedule() }
                        macro.schedule?.enabled = $0
                    }
                ))

                if macro.schedule?.enabled == true {
                    LabeledContent("macro.schedule.interval") {
                        Stepper(
                            value: Binding(
                                get: { macro.schedule?.intervalMinutes ?? 60 },
                                set: { macro.schedule?.intervalMinutes = $0 }
                            ),
                            in: 1...1440
                        ) {
                            Text("\(macro.schedule?.intervalMinutes ?? 60) min")
                        }
                    }

                    Toggle("macro.schedule.on_connect", isOn: Binding(
                        get: { macro.schedule?.runOnConnect ?? false },
                        set: { macro.schedule?.runOnConnect = $0 }
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            commandsText = macro.commands.joined(separator: "\n")
        }
        .onChange(of: macro.id) { _, _ in
            commandsText = macro.commands.joined(separator: "\n")
        }
    }
}

// MARK: - MacroMenuItems (View wrapper for @Environment)
// Note: Uses @FocusedValue to safely access AppViewModel from menu commands

struct MacroMenuItems: View {
    @FocusedValue(\.macroExecutorVM) private var executorVM
    // Note: openWindow is handled in MacroManagerOpener (nested View) — do NOT
    // declare it twice here, that caused undefined behaviour (duplicate property).
    @State private var macroService = MacroService.shared

    var body: some View {
        MacroManagerOpener()
        if !macroService.macros.isEmpty {
            Divider()
            ForEach(macroService.macros.prefix(10)) { macro in
                Button(macro.name.isEmpty ? String(localized: "macro.new") : macro.name) {
                    if let sessions = executorVM {
                        macroService.executeMacro(macro, in: sessions)
                    }
                }
            }
        }
    }
}

private struct MacroManagerOpener: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("menu.macros.manager") {
            openWindow(id: "macros")
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}
