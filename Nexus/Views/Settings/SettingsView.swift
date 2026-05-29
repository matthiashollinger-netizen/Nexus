import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general  = "settings.general"
        case terminal = "settings.terminal"
        case ssh      = "settings.ssh"
        case security = "settings.security"
        case syntax   = "settings.syntax"
        var id: String { rawValue }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("settings.general", systemImage: "gear") }
                .tag(SettingsTab.general)

            TerminalSettingsView()
                .tabItem { Label("settings.terminal", systemImage: "terminal") }
                .tag(SettingsTab.terminal)

            SSHSettingsView()
                .tabItem { Label("settings.ssh", systemImage: "lock.fill") }
                .tag(SettingsTab.ssh)

            SecuritySettingsView()
                .tabItem { Label("settings.security", systemImage: "shield") }
                .tag(SettingsTab.security)

            SyntaxRulesEditorView()
                .tabItem { Label("settings.syntax", systemImage: "text.badge.checkmark") }
                .tag(SettingsTab.syntax)
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(UpdaterViewModel.self) private var updaterVM

    var body: some View {
        @Bindable var vm = vm
        Form {
            Section("settings.language") {
                Picker("settings.language", selection: $vm.settings.language) {
                    Text("English").tag("en")
                    Text("Deutsch").tag("de")
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.settings.language) { _, _ in
                    vm.saveSettings()
                }
            }

            Section("settings.updates") {
                Button("settings.updates.check") {
                    updaterVM.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Terminal

struct TerminalSettingsView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var previewText = "$ echo Hello Nexus\nHello Nexus\n$ _"

    var body: some View {
        @Bindable var vm = vm
        Form {
            Section("settings.terminal.font") {
                LabeledContent("settings.font_name") {
                    Picker("", selection: $vm.settings.terminalFontName) {
                        Text("Menlo").tag("Menlo")
                        Text("Monaco").tag("Monaco")
                        Text("Courier New").tag("Courier New")
                        Text("SF Mono").tag("SFMono-Regular")
                        Text("JetBrains Mono").tag("JetBrainsMono-Regular")
                    }
                }
                LabeledContent("settings.font_size") {
                    Stepper(value: $vm.settings.terminalFontSize, in: 8...24, step: 1) {
                        Text("\(Int(vm.settings.terminalFontSize)) pt")
                    }
                }
            }
            Section("settings.terminal.preview") {
                Text(previewText)
                    .font(.custom(vm.settings.terminalFontName, size: vm.settings.terminalFontSize))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black)
                    .foregroundStyle(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: vm.settings.terminalFontName) { _, _ in vm.saveSettings() }
        .onChange(of: vm.settings.terminalFontSize) { _, _ in vm.saveSettings() }
    }
}

// MARK: - SSH

struct SSHSettingsView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        Form {
            Section {
                Toggle("settings.ssh.legacy_algorithms", isOn: $vm.settings.sshLegacyAlgorithms)
            } header: {
                Text("settings.ssh.legacy")
            } footer: {
                Text("settings.ssh.legacy_hint")
                    .font(.caption)
            }

            Section("settings.ssh.defaults") {
                LabeledContent("session.port") {
                    TextField("", value: $vm.settings.defaultSSHPort, format: .number)
                        .frame(width: 80)
                }
                LabeledContent("settings.telnet.port") {
                    TextField("", value: $vm.settings.defaultTelnetPort, format: .number)
                        .frame(width: 80)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: vm.settings.sshLegacyAlgorithms) { _, _ in vm.saveSettings() }
        .onChange(of: vm.settings.defaultSSHPort) { _, _ in vm.saveSettings() }
        .onChange(of: vm.settings.defaultTelnetPort) { _, _ in vm.saveSettings() }
    }
}

// MARK: - Security

struct SecuritySettingsView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var showChangeMasterPassword = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil

    var body: some View {
        @Bindable var vm = vm
        Form {
            Section {
                Toggle("settings.security.master_password", isOn: $vm.settings.masterPasswordEnabled)
                    .onChange(of: vm.settings.masterPasswordEnabled) { _, enabled in
                        if enabled {
                            showChangeMasterPassword = true
                        } else {
                            vm.saveSettings()
                        }
                    }
            } footer: {
                Text("settings.security.master_password_hint")
                    .font(.caption)
            }

            if vm.settings.masterPasswordEnabled {
                Section("settings.security.change_password") {
                    SecureField("settings.security.current_password", text: $currentPassword)
                    SecureField("settings.security.new_password", text: $newPassword)
                    SecureField("settings.security.confirm_password", text: $confirmNewPassword)

                    if let error = errorMessage {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                    if let success = successMessage {
                        Text(success).foregroundStyle(.green).font(.caption)
                    }

                    Button("settings.security.change_password_btn") {
                        changeMasterPassword()
                    }
                    .disabled(currentPassword.isEmpty || newPassword.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func changeMasterPassword() {
        // Always clear both messages first
        errorMessage = nil
        successMessage = nil

        guard newPassword == confirmNewPassword else {
            errorMessage = String(localized: "masterpassword.mismatch")
            return
        }
        do {
            let creds = try vm.db.loadCredentials(masterPassword: currentPassword)
            try vm.db.saveCredentials(creds, masterPassword: newPassword)
            vm.masterPassword = newPassword
            // Update keychain if password was stored there
            if KeychainService.hasMasterPasswordInKeychain {
                try? KeychainService.saveMasterPassword(newPassword)
            }
            successMessage = String(localized: "settings.security.password_changed")
            currentPassword = ""
            newPassword = ""
            confirmNewPassword = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Syntax Rules Editor

struct SyntaxRulesEditorView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var highlighter = TerminalHighlighter.shared

    private struct RulesetInfo: Identifiable {
        let id: HighlightRuleset
        let nameKey: LocalizedStringKey
        let descKey: LocalizedStringKey
    }

    private let rulesets: [RulesetInfo] = [
        .init(id: .default, nameKey: "syntax.ruleset.default",
              descKey: "syntax.ruleset.default"),
        .init(id: .logLevel, nameKey: "syntax.ruleset.log",
              descKey: "syntax.ruleset.log"),
        .init(id: .ciscoIOS, nameKey: "syntax.ruleset.cisco",
              descKey: "syntax.ruleset.cisco"),
        .init(id: .network,  nameKey: "syntax.ruleset.network",
              descKey: "syntax.ruleset.network"),
    ]

    var body: some View {
        @Bindable var vm = vm
        Form {
            Section("syntax.rulesets") {
                ForEach(rulesets) { info in
                    Toggle(info.nameKey, isOn: Binding(
                        get: { vm.settings.enabledHighlightRulesets.contains(info.id.rawValue) },
                        set: { enabled in
                            if enabled {
                                if !vm.settings.enabledHighlightRulesets.contains(info.id.rawValue) {
                                    vm.settings.enabledHighlightRulesets.append(info.id.rawValue)
                                }
                            } else {
                                vm.settings.enabledHighlightRulesets.removeAll { $0 == info.id.rawValue }
                            }
                            vm.saveSettings()
                            TerminalHighlighter.shared.updateEnabledRulesets(vm.settings.enabledHighlightRulesets)
                        }
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            TerminalHighlighter.shared.updateEnabledRulesets(vm.settings.enabledHighlightRulesets)
        }
    }
}
