import SwiftUI

// MARK: - Network Toolbox
//
// MobaXterm-style network tools, all driven by macOS system binaries (ping,
// traceroute, dig, nc) plus a native Wake-on-LAN. Self-contained, no installs.

enum NetTool: String, CaseIterable, Identifiable {
    case ping, traceroute, dns, port, wol
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .ping: return "toolbox.ping"
        case .traceroute: return "toolbox.traceroute"
        case .dns: return "toolbox.dns"
        case .port: return "toolbox.port"
        case .wol: return "toolbox.wol"
        }
    }
    var icon: String {
        switch self {
        case .ping: return "wave.3.right"
        case .traceroute: return "point.topleft.down.to.point.bottomright.curvepath"
        case .dns: return "globe"
        case .port: return "lock.open"
        case .wol: return "power"
        }
    }
}

struct NetworkToolboxView: View {
    @State private var selected: NetTool = .ping
    @State private var host = ""
    @State private var port = "22"
    @State private var mac = ""
    @State private var runner = NetworkToolRunner()
    @State private var wolStatus: LocalizedStringKey? = nil

    var body: some View {
        HSplitView {
            toolList
                .frame(minWidth: 170, maxWidth: 200)
            detail
                .frame(minWidth: 420)
        }
        .frame(minWidth: 660, minHeight: 460)
    }

    // MARK: Tool list

    private var toolList: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            SectionHeader("toolbox.title").padding(.horizontal, DS.Space.md).padding(.top, DS.Space.lg)
            ForEach(NetTool.allCases) { tool in
                Button { selected = tool; runner.stop(); wolStatus = nil } label: {
                    Label(tool.title, systemImage: tool.icon)
                        .font(DS.Font.body)
                        .foregroundStyle(selected == tool ? DS.Color.accent : DS.Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Space.md).padding(.vertical, DS.Space.sm)
                        .background(selected == tool ? DS.Color.rowSelected : .clear,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Space.sm)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            inputs
            if selected == .wol, let status = wolStatus {
                InfoCard(style: .info, message: status)
            }
            if selected != .wol {
                outputPane
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.xl)
    }

    @ViewBuilder private var inputs: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if selected == .wol {
                LabeledContent("toolbox.mac") {
                    TextField("AA:BB:CC:DD:EE:FF", text: $mac).font(DS.Font.mono).frame(width: 200)
                }
            } else {
                HStack {
                    LabeledContent("toolbox.host") {
                        TextField("192.168.1.1 / example.com", text: $host)
                            .font(DS.Font.mono).frame(width: 220)
                            .onSubmit(run)
                    }
                    if selected == .port {
                        LabeledContent("toolbox.port_field") {
                            TextField("22", text: $port).font(DS.Font.mono).frame(width: 60)
                        }
                    }
                }
            }
            HStack(spacing: DS.Space.md) {
                Button(action: run) {
                    Label(runner.isRunning ? "toolbox.running" : "toolbox.run",
                          systemImage: runner.isRunning ? "hourglass" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(runner.isRunning || !isValid)
                if runner.isRunning {
                    Button("toolbox.stop") { runner.stop() }.buttonStyle(.bordered)
                }
            }
        }
    }

    private var outputPane: some View {
        ScrollView {
            Text(runner.output.isEmpty ? " " : runner.output)
                .font(DS.Font.mono)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(DS.Space.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.hairline, lineWidth: 0.5))
    }

    private var isValid: Bool {
        switch selected {
        case .wol: return !mac.trimmingCharacters(in: .whitespaces).isEmpty
        default:   return !host.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func run() {
        let h = host.trimmingCharacters(in: .whitespaces)
        switch selected {
        case .ping:
            runner.run(executable: "/sbin/ping", args: ["-c", "5", "-t", "5", h])
        case .traceroute:
            runner.run(executable: "/usr/sbin/traceroute", args: ["-n", "-w", "2", "-q", "1", h])
        case .dns:
            runner.run(executable: "/usr/bin/dig", args: ["+nostats", h])
        case .port:
            let p = port.trimmingCharacters(in: .whitespaces)
            runner.run(executable: "/usr/bin/nc", args: ["-vz", "-G", "3", h, p])
        case .wol:
            switch WakeOnLANService.wake(mac: mac) {
            case .sent: wolStatus = "toolbox.wol.sent"
            case .invalidMAC: wolStatus = "toolbox.wol.invalid"
            case .failed: wolStatus = "toolbox.wol.failed"
            }
        }
    }
}
