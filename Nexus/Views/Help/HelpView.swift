import SwiftUI

// MARK: - Help window (Help → Nexus Hilfe)

struct HelpView: View {
    @State private var selected: HelpTopic = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selected) { topic in
                Label(topic.title, systemImage: topic.icon)
                    .tag(topic)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            HelpDetailView(topic: selected)
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}

// MARK: - Topics

enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted
    case ssh
    case telnet
    case serial
    case sidebar
    case tabs
    case passwordManager
    case csvImport
    case settings
    case shortcuts

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .gettingStarted:   return "help.topic.start"
        case .ssh:              return "help.topic.ssh"
        case .telnet:           return "help.topic.telnet"
        case .serial:           return "help.topic.serial"
        case .sidebar:          return "help.topic.sidebar"
        case .tabs:             return "help.topic.tabs"
        case .passwordManager:  return "help.topic.pwmgr"
        case .csvImport:        return "help.topic.import"
        case .settings:         return "help.topic.settings"
        case .shortcuts:        return "help.topic.shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted:   return "star.fill"
        case .ssh:              return "lock.fill"
        case .telnet:           return "network"
        case .serial:           return "cable.connector"
        case .sidebar:          return "sidebar.left"
        case .tabs:             return "rectangle.split.2x1"
        case .passwordManager:  return "key.fill"
        case .csvImport:        return "doc.text"
        case .settings:         return "gearshape.fill"
        case .shortcuts:        return "keyboard"
        }
    }
}

// MARK: - Detail view

struct HelpDetailView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 14) {
                    Image(systemName: topic.icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(topic.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .padding(.bottom, 20)

                // Content
                switch topic {
                case .gettingStarted:   GettingStartedHelp()
                case .ssh:              SSHHelp()
                case .telnet:           TelnetHelp()
                case .serial:           SerialHelp()
                case .sidebar:          SidebarHelp()
                case .tabs:             TabsHelp()
                case .passwordManager:  PasswordManagerHelp()
                case .csvImport:        CSVImportHelp()
                case .settings:         SettingsHelp()
                case .shortcuts:        ShortcutsHelp()
                }
            }
            .padding(32)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Reusable components

private struct HelpSection<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top, 24)
            .padding(.bottom, 2)

            content
        }
    }
}

private struct HelpStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HelpTip: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
                .padding(.top, 2)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct HelpKeyValue: View {
    let key: LocalizedStringKey
    let value: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .fontWeight(.medium)
                .frame(width: 160, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ShortcutRow: View {
    let shortcut: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack {
            Text(description)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
        }
    }
}

// MARK: - Content: Getting Started

private struct GettingStartedHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("help.start.intro")
                .foregroundStyle(.secondary)

            HelpSection(title: "help.start.first_steps", icon: "play.fill") {
                HelpStep(number: 1, text: "help.start.step1")
                HelpStep(number: 2, text: "help.start.step2")
                HelpStep(number: 3, text: "help.start.step3")
                HelpStep(number: 4, text: "help.start.step4")
            }

            HelpSection(title: "help.start.overview", icon: "rectangle.split.2x1") {
                HelpKeyValue(key: "help.start.sidebar_label",  value: "help.start.sidebar_desc")
                HelpKeyValue(key: "help.start.tabs_label",     value: "help.start.tabs_desc")
                HelpKeyValue(key: "help.start.terminal_label", value: "help.start.terminal_desc")
            }

            HelpTip(text: "help.start.tip")
        }
    }
}

// MARK: - Content: SSH

private struct SSHHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("help.ssh.intro").foregroundStyle(.secondary)

            HelpSection(title: "help.ssh.connect", icon: "play.fill") {
                HelpStep(number: 1, text: "help.ssh.step1")
                HelpStep(number: 2, text: "help.ssh.step2")
                HelpStep(number: 3, text: "help.ssh.step3")
            }

            HelpSection(title: "help.ssh.auth", icon: "key.fill") {
                HelpKeyValue(key: "help.ssh.auth_pw",  value: "help.ssh.auth_pw_desc")
                HelpKeyValue(key: "help.ssh.auth_key", value: "help.ssh.auth_key_desc")
            }

            HelpSection(title: "help.ssh.options", icon: "gearshape") {
                HelpKeyValue(key: "help.ssh.legacy_label",    value: "help.ssh.legacy_desc")
                HelpKeyValue(key: "help.ssh.strictkey_label", value: "help.ssh.strictkey_desc")
                HelpKeyValue(key: "help.ssh.knownhosts",      value: "help.ssh.knownhosts_desc")
            }

            HelpTip(text: "help.ssh.tip")
        }
    }
}

// MARK: - Content: Telnet

private struct TelnetHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("help.telnet.intro").foregroundStyle(.secondary)

            HelpSection(title: "help.telnet.connect", icon: "play.fill") {
                HelpStep(number: 1, text: "help.telnet.step1")
                HelpStep(number: 2, text: "help.telnet.step2")
            }

            HelpSection(title: "help.telnet.settings", icon: "gearshape") {
                HelpKeyValue(key: "help.telnet.port_label", value: "help.telnet.port_desc")
            }

            HelpTip(text: "help.telnet.tip")
        }
    }
}

// MARK: - Content: Serial

private struct SerialHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("help.serial.intro").foregroundStyle(.secondary)

            HelpSection(title: "help.serial.connect", icon: "play.fill") {
                HelpStep(number: 1, text: "help.serial.step1")
                HelpStep(number: 2, text: "help.serial.step2")
                HelpStep(number: 3, text: "help.serial.step3")
            }

            HelpSection(title: "help.serial.params", icon: "slider.horizontal.3") {
                HelpKeyValue(key: "help.serial.baud",     value: "help.serial.baud_desc")
                HelpKeyValue(key: "help.serial.databits", value: "help.serial.databits_desc")
                HelpKeyValue(key: "help.serial.parity",   value: "help.serial.parity_desc")
                HelpKeyValue(key: "help.serial.stopbits", value: "help.serial.stopbits_desc")
                HelpKeyValue(key: "help.serial.flow",     value: "help.serial.flow_desc")
            }

            HelpTip(text: "help.serial.tip")
        }
    }
}

// MARK: - Content: Sidebar

private struct SidebarHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("help.sidebar.intro").foregroundStyle(.secondary)

            HelpSection(title: "help.sidebar.sessions", icon: "terminal") {
                HelpKeyValue(key: "help.sidebar.new",       value: "help.sidebar.new_desc")
                HelpKeyValue(key: "help.sidebar.connect",   value: "help.sidebar.connect_desc")
                HelpKeyValue(key: "help.sidebar.edit",      value: "help.sidebar.edit_desc")
                HelpKeyValue(key: "help.sidebar.delete",    value: "help.sidebar.delete_desc")
                HelpKeyValue(key: "help.sidebar.search",    value: "help.sidebar.search_desc")
            }

            HelpSection(title: "help.sidebar.folders", icon: "folder.fill") {
                HelpKeyValue(key: "help.sidebar.folder_new",      value: "help.sidebar.folder_new_desc")
                HelpKeyValue(key: "help.sidebar.folder_cred",     value: "help.sidebar.folder_cred_desc")
                HelpKeyValue(key: "help.sidebar.folder_expand",   value: "help.sidebar.folder_expand_desc")
            }

            HelpTip(text: "help.sidebar.tip")
        }
    }
}

// MARK: - Content: Tabs

private struct TabsHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("help.tabs.intro").foregroundStyle(.secondary)

            HelpSection(title: "help.tabs.usage", icon: "rectangle.split.2x1") {
                HelpKeyValue(key: "help.tabs.open",      value: "help.tabs.open_desc")
                HelpKeyValue(key: "help.tabs.switch",    value: "help.tabs.switch_desc")
                HelpKeyValue(key: "help.tabs.reorder",   value: "help.tabs.reorder_desc")
                HelpKeyValue(key: "help.tabs.close",     value: "help.tabs.close_desc")
            }

            HelpSection(title: "help.tabs.reconnect", icon: "bolt.fill") {
                HelpKeyValue(key: "help.tabs.reconnect_auto",   value: "help.tabs.reconnect_auto_desc")
                HelpKeyValue(key: "help.tabs.reconnect_manual", value: "help.tabs.reconnect_manual_desc")
                HelpKeyValue(key: "help.tabs.reconnect_key",    value: "help.tabs.reconnect_key_desc")
            }

            HelpTip(text: "help.tabs.tip")
        }
    }
}

// MARK: - Content: Password Manager

private struct PasswordManagerHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("help.pwmgr.intro").foregroundStyle(.secondary)

            HelpSection(title: "help.pwmgr.features", icon: "lock.shield.fill") {
                HelpKeyValue(key: "help.pwmgr.encrypt",  value: "help.pwmgr.encrypt_desc")
                HelpKeyValue(key: "help.pwmgr.link",     value: "help.pwmgr.link_desc")
                HelpKeyValue(key: "help.pwmgr.inherit",  value: "help.pwmgr.inherit_desc")
                HelpKeyValue(key: "help.pwmgr.export",   value: "help.pwmgr.export_desc")
            }

            HelpSection(title: "help.pwmgr.setup", icon: "gearshape") {
                HelpStep(number: 1, text: "help.pwmgr.step1")
                HelpStep(number: 2, text: "help.pwmgr.step2")
                HelpStep(number: 3, text: "help.pwmgr.step3")
            }

            HelpTip(text: "help.pwmgr.tip")
        }
    }
}

// MARK: - Content: CSV Import

private struct CSVImportHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("help.import.intro").foregroundStyle(.secondary)

            HelpSection(title: "help.import.steps", icon: "doc.text") {
                HelpStep(number: 1, text: "help.import.step1")
                HelpStep(number: 2, text: "help.import.step2")
                HelpStep(number: 3, text: "help.import.step3")
                HelpStep(number: 4, text: "help.import.step4")
            }

            HelpSection(title: "help.import.fields", icon: "list.bullet") {
                HelpKeyValue(key: "help.import.field_name",   value: "help.import.field_name_desc")
                HelpKeyValue(key: "help.import.field_host",   value: "help.import.field_host_desc")
                HelpKeyValue(key: "help.import.field_proto",  value: "help.import.field_proto_desc")
                HelpKeyValue(key: "help.import.field_port",   value: "help.import.field_port_desc")
                HelpKeyValue(key: "help.import.field_user",   value: "help.import.field_user_desc")
                HelpKeyValue(key: "help.import.field_folder", value: "help.import.field_folder_desc")
            }

            HelpTip(text: "help.import.tip")
        }
    }
}

// MARK: - Content: Settings

private struct SettingsHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("help.settings.intro").foregroundStyle(.secondary)

            HelpSection(title: "help.settings.general_sec", icon: "gear") {
                HelpKeyValue(key: "help.settings.language",  value: "help.settings.language_desc")
                HelpKeyValue(key: "help.settings.updates",   value: "help.settings.updates_desc")
            }
            HelpSection(title: "help.settings.terminal_sec", icon: "terminal") {
                HelpKeyValue(key: "help.settings.font",      value: "help.settings.font_desc")
                HelpKeyValue(key: "help.settings.fontsize",  value: "help.settings.fontsize_desc")
            }
            HelpSection(title: "help.settings.ssh_sec", icon: "lock.fill") {
                HelpKeyValue(key: "help.settings.legacy",    value: "help.settings.legacy_desc")
                HelpKeyValue(key: "help.settings.ports",     value: "help.settings.ports_desc")
            }
            HelpSection(title: "help.settings.security_sec", icon: "shield.fill") {
                HelpKeyValue(key: "help.settings.master_pw", value: "help.settings.master_pw_desc")
                HelpKeyValue(key: "help.settings.change_pw", value: "help.settings.change_pw_desc")
            }
        }
    }
}

// MARK: - Content: Shortcuts

private struct ShortcutsHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("help.shortcuts.intro").foregroundStyle(.secondary)

            HelpSection(title: "help.shortcuts.general_sec", icon: "command") {
                ShortcutRow(shortcut: "⌘N",       description: "help.sc.new_session")
                ShortcutRow(shortcut: "⇧⌘N",      description: "help.sc.new_folder")
                ShortcutRow(shortcut: "⌘E",       description: "help.sc.edit")
                ShortcutRow(shortcut: "⌦",        description: "help.sc.delete")
                ShortcutRow(shortcut: "⇧⌘K",      description: "help.sc.pwmgr")
                ShortcutRow(shortcut: "⌘,",       description: "help.sc.settings")
            }
            HelpSection(title: "help.shortcuts.terminal_sec", icon: "terminal") {
                ShortcutRow(shortcut: "R / ↩",    description: "help.sc.reconnect")
                ShortcutRow(shortcut: "help.sc.dblclick_label", description: "help.sc.connect")
            }
        }
    }
}
