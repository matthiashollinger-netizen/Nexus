import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Theme Editor Window

struct ThemeEditorView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var themeService = ThemeService.shared
    @State private var selectedThemeId: UUID? = nil
    @State private var editorTab: EditorTab = .terminal

    enum EditorTab: String, CaseIterable {
        case terminal = "theme.terminal"
        case ui       = "theme.ui"
        case typography = "theme.typography"
        case behavior = "theme.behavior"
    }

    private var selectedTheme: Binding<NexusTheme>? {
        guard let id = selectedThemeId,
              let idx = themeService.themes.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.themeService.themes[idx] },
            set: { self.themeService.themes[idx] = $0; self.themeService.saveThemes() }
        )
    }

    var body: some View {
        HSplitView {
            // Left: Theme list
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(themeService.themes) { theme in
                            ThemeListRow(
                                theme: theme,
                                isSelected: selectedThemeId == theme.id,
                                isActive: themeService.activeThemeId == theme.id
                            )
                            .onTapGesture { selectedThemeId = theme.id }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .listStyle(.sidebar)
                .onAppear { selectedThemeId = themeService.activeThemeId }

                Divider()

                HStack {
                    Button {
                        addTheme()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        duplicateTheme()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedThemeId == nil)

                    Button {
                        deleteTheme()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedTheme?.wrappedValue.isBuiltIn ?? true)

                    Spacer()

                    if let binding = selectedTheme {
                        Button {
                            if let url = try? themeService.exportTheme(binding.wrappedValue) {
                                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .help("theme.export")
                    }

                    Button {
                        importTheme()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .help("theme.import")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(minWidth: 180, maxWidth: 240)

            // Right: Editor
            if let binding = selectedTheme {
                VStack(spacing: 0) {
                    // Activate button
                    HStack {
                        Text(binding.wrappedValue.name)
                            .font(.headline)
                        Spacer()
                        Button("theme.active") {
                            themeService.applyTheme(binding.wrappedValue)
                            vm.saveSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(themeService.activeThemeId == binding.wrappedValue.id)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    // Tabs
                    TabView(selection: $editorTab) {
                        ThemeTerminalTab(theme: binding)
                            .tabItem { Text(LocalizedStringKey("theme.terminal")) }
                            .tag(EditorTab.terminal)

                        ThemeUITab(theme: binding)
                            .tabItem { Text(LocalizedStringKey("theme.ui")) }
                            .tag(EditorTab.ui)

                        ThemeTypographyTab(theme: binding)
                            .tabItem { Text(LocalizedStringKey("theme.typography")) }
                            .tag(EditorTab.typography)

                        ThemeBehaviorTab(theme: binding)
                            .tabItem { Text(LocalizedStringKey("theme.behavior")) }
                            .tag(EditorTab.behavior)
                    }
                    .disabled(binding.wrappedValue.isBuiltIn)
                }
            } else {
                VStack {
                    Spacer()
                    Text("theme.select_hint")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear { themeService.loadThemes() }
    }

    private func addTheme() {
        var theme = NexusTheme.nexusDark
        theme.id = UUID()
        theme.name = "Custom Theme"
        theme.isBuiltIn = false
        themeService.themes.append(theme)
        themeService.saveThemes()
        selectedThemeId = theme.id
    }

    private func duplicateTheme() {
        guard let src = selectedTheme?.wrappedValue else { return }
        var copy = src
        copy.id = UUID()
        copy.name = src.name + " Copy"
        copy.isBuiltIn = false
        themeService.themes.append(copy)
        themeService.saveThemes()
        selectedThemeId = copy.id
    }

    private func deleteTheme() {
        guard let id = selectedThemeId,
              themeService.themes.first(where: { $0.id == id })?.isBuiltIn == false else { return }
        themeService.themes.removeAll { $0.id == id }
        themeService.saveThemes()
        selectedThemeId = themeService.themes.first?.id
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "nexustheme")!]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? themeService.importTheme(from: url)
        }
    }
}

// MARK: - Terminal Color Tab

struct ThemeTerminalTab: View {
    @Binding var theme: NexusTheme

    var body: some View {
        ScrollView {
            Form {
                Section("theme.preview") {
                    ThemePreviewView(theme: theme)
                }

                Section("theme.terminal") {
                    ColorRow("theme.background", color: colorBinding(\.terminalBackground))
                    ColorRow("theme.foreground", color: colorBinding(\.terminalForeground))
                    ColorRow("theme.cursor",     color: colorBinding(\.terminalCursorColor))
                }

                Section("theme.ansi_colors") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                        GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(0..<min(16, theme.ansiColors.count), id: \.self) { i in
                            ColorSwatch(index: i, color: ansiColorBinding(at: i))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    private func colorBinding(_ kp: WritableKeyPath<NexusTheme, CodableColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: theme[keyPath: kp].nsColor) },
            set: { newColor in
                if let c = NSColor(newColor).usingColorSpace(.sRGB) {
                    theme[keyPath: kp] = CodableColor(red: Double(c.redComponent),
                                                       green: Double(c.greenComponent),
                                                       blue: Double(c.blueComponent),
                                                       alpha: Double(c.alphaComponent))
                }
            }
        )
    }

    private func ansiColorBinding(at index: Int) -> Binding<Color> {
        Binding(
            get: {
                guard index < theme.ansiColors.count else { return .black }
                return Color(nsColor: theme.ansiColors[index].nsColor)
            },
            set: { newColor in
                guard index < theme.ansiColors.count else { return }
                if let c = NSColor(newColor).usingColorSpace(.sRGB) {
                    theme.ansiColors[index] = CodableColor(red: Double(c.redComponent),
                                                            green: Double(c.greenComponent),
                                                            blue: Double(c.blueComponent))
                }
            }
        )
    }
}

// MARK: - UI Tab

struct ThemeUITab: View {
    @Binding var theme: NexusTheme

    var body: some View {
        Form {
            Section {
                ColorRow("theme.sidebar_bg", color: colorBinding(\.sidebarBackground))
                ColorRow("theme.accent",     color: colorBinding(\.accentColor))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func colorBinding(_ kp: WritableKeyPath<NexusTheme, CodableColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: theme[keyPath: kp].nsColor) },
            set: { newColor in
                if let c = NSColor(newColor).usingColorSpace(.sRGB) {
                    theme[keyPath: kp] = CodableColor(red: Double(c.redComponent),
                                                       green: Double(c.greenComponent),
                                                       blue: Double(c.blueComponent))
                }
            }
        )
    }
}

// MARK: - Typography Tab

struct ThemeTypographyTab: View {
    @Binding var theme: NexusTheme

    var body: some View {
        Form {
            Section("theme.typography") {
                LabeledContent("theme.font") {
                    Picker("", selection: $theme.terminalFont) {
                        Text("Menlo").tag("Menlo")
                        Text("Monaco").tag("Monaco")
                        Text("Courier New").tag("Courier New")
                        Text("SF Mono").tag("SFMono-Regular")
                        Text("JetBrains Mono").tag("JetBrainsMono-Regular")
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                LabeledContent("theme.font_size") {
                    Stepper(value: $theme.terminalFontSize, in: 8...36, step: 0.5) {
                        Text(String(format: "%.1f pt", theme.terminalFontSize))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Behavior Tab

struct ThemeBehaviorTab: View {
    @Binding var theme: NexusTheme

    var body: some View {
        Form {
            Section("theme.behavior") {
                LabeledContent("theme.cursor.style") {
                    Picker("", selection: $theme.cursorStyle) {
                        ForEach(NexusTheme.CursorStyle.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                Toggle("theme.cursor.blink", isOn: $theme.cursorBlink)
                LabeledContent("theme.scrollback") {
                    Stepper(value: $theme.scrollbackLines, in: 100...100000, step: 1000) {
                        Text("\(theme.scrollbackLines)")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Theme List Row

private struct ThemeListRow: View {
    let theme: NexusTheme
    let isSelected: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            ThemeColorChip(color: theme.terminalBackground.nsColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(theme.name)
                    .font(.system(size: 12))
                if theme.isBuiltIn {
                    Text("Built-in")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }
}

private struct ThemeColorChip: View {
    let color: NSColor

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(nsColor: color))
            .frame(width: 24, height: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - Helpers

private struct ColorRow: View {
    let label: LocalizedStringKey
    @Binding var color: Color

    init(_ label: LocalizedStringKey, color: Binding<Color>) {
        self.label = label
        self._color = color
    }

    var body: some View {
        LabeledContent(label) {
            ColorPicker("", selection: $color)
                .labelsHidden()
        }
    }
}

private struct ColorSwatch: View {
    let index: Int
    @Binding var color: Color

    var body: some View {
        ColorPicker(String(index), selection: $color)
            .labelsHidden()
            .frame(maxWidth: .infinity)
    }
}

private struct ThemePreviewView: View {
    let theme: NexusTheme

    var body: some View {
        let font = Font.custom(theme.terminalFont, size: theme.terminalFontSize)
        VStack(alignment: .leading, spacing: 2) {
            Text("$ ssh admin@192.168.1.1")
                .foregroundStyle(Color(nsColor: theme.terminalForeground.nsColor))
            Text("Welcome to Nexus!")
                .foregroundStyle(.green)
            Text("admin@router:~$ _")
                .foregroundStyle(Color(nsColor: theme.terminalForeground.nsColor))
        }
        .font(font)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: theme.terminalBackground.nsColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
