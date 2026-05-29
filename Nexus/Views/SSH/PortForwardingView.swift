import SwiftUI

// MARK: - Gateway Section (used inside AddSessionView)

struct GatewaySection: View {
    @Binding var draft: Session

    var body: some View {
        // ── Jump Host ────────────────────────────────────────────────────────
        Section {
            Toggle("gateway.jump_host.enabled", isOn: Binding(
                get: { draft.jumpHost != nil },
                set: { enabled in
                    draft.jumpHost = enabled ? JumpHost() : nil
                }
            ))

            if draft.jumpHost != nil {
                LabeledContent("gateway.jump_host.host") {
                    TextField("", text: Binding(
                        get: { draft.jumpHost?.host ?? "" },
                        set: { draft.jumpHost?.host = $0 }
                    ))
                }
                LabeledContent("session.port") {
                    TextField("", value: Binding(
                        get: { draft.jumpHost?.port ?? 22 },
                        set: { draft.jumpHost?.port = $0 }
                    ), format: .number)
                    .frame(width: 70)
                }
                LabeledContent("session.username") {
                    TextField("", text: Binding(
                        get: { draft.jumpHost?.username ?? "" },
                        set: { draft.jumpHost?.username = $0 }
                    ))
                }
            }
        } header: {
            Text("gateway.section.jump_host")
        }

        // ── Port Forwardings ─────────────────────────────────────────────────
        Section {
            ForEach($draft.portForwardings) { $fwd in
                PortForwardingRow(fwd: $fwd) {
                    draft.portForwardings.removeAll { $0.id == fwd.id }
                }
            }

            Button {
                draft.portForwardings.append(PortForwarding())
            } label: {
                Label("gateway.fwd.add", systemImage: "plus.circle")
            }
        } header: {
            Text("gateway.section.forwardings")
        } footer: {
            Text("gateway.fwd.hint")
                .font(.caption).foregroundStyle(.secondary)
        }

        // ── SOCKS5 ───────────────────────────────────────────────────────────
        Section {
            Toggle("gateway.socks5.enabled", isOn: Binding(
                get: { draft.socks5Proxy?.enabled ?? false },
                set: { enabled in
                    if draft.socks5Proxy == nil { draft.socks5Proxy = SOCKS5Config() }
                    draft.socks5Proxy?.enabled = enabled
                }
            ))

            if draft.socks5Proxy?.enabled == true {
                LabeledContent("gateway.socks5.port") {
                    TextField("", value: Binding(
                        get: { draft.socks5Proxy?.localPort ?? 1080 },
                        set: { draft.socks5Proxy?.localPort = $0 }
                    ), format: .number)
                    .frame(width: 80)
                }
                Text("gateway.socks5.hint")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("gateway.section.socks5")
        }
    }
}

// MARK: - Single Port Forwarding Row

private struct PortForwardingRow: View {
    @Binding var fwd: PortForwarding
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $fwd.type) {
                    ForEach(PortForwarding.ForwardingType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .frame(width: 180)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            if fwd.type == .dynamic {
                HStack {
                    Text("gateway.fwd.local_port").font(.caption).foregroundStyle(.secondary)
                    TextField("8080", value: $fwd.localPort, format: .number)
                        .frame(width: 70)
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    TextField("gateway.fwd.local_port", value: $fwd.localPort, format: .number)
                        .frame(width: 70)
                        .help("gateway.fwd.local_port")
                    Text("→").foregroundStyle(.secondary)
                    TextField("gateway.fwd.remote_host", text: $fwd.remoteHost)
                        .help("gateway.fwd.remote_host")
                    Text(":").foregroundStyle(.secondary)
                    TextField("", value: $fwd.remotePort, format: .number)
                        .frame(width: 70)
                        .help("gateway.fwd.remote_port")
                }
                .font(.callout)
            }

            if !fwd.description.isEmpty || true {
                TextField("gateway.fwd.description", text: $fwd.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Active Port Forwardings Sheet (shown from tab toolbar)

struct PortForwardingStatusView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("gateway.status.title").font(.headline)
                    Text(session.host).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("action.close") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            if session.portForwardings.isEmpty && session.socks5Proxy?.enabled != true && session.jumpHost == nil {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("gateway.status.none")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Jump Host
                    if let j = session.jumpHost, !j.host.isEmpty {
                        Section("gateway.section.jump_host") {
                            HStack {
                                Circle().fill(.green).frame(width: 8, height: 8)
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.secondary)
                                Text(j.username.isEmpty ? j.host : "\(j.username)@\(j.host):\(j.port)")
                                    .font(.callout.monospaced())
                            }
                        }
                    }

                    // Port Forwardings
                    if !session.portForwardings.isEmpty {
                        Section("gateway.section.forwardings") {
                            ForEach(session.portForwardings) { fwd in
                                ForwardingStatusRow(fwd: fwd)
                            }
                        }
                    }

                    // SOCKS5
                    if let socks = session.socks5Proxy, socks.enabled {
                        Section("gateway.section.socks5") {
                            HStack {
                                Circle().fill(.green).frame(width: 8, height: 8)
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                                Text("SOCKS5 → localhost:\(socks.localPort)")
                                    .font(.callout.monospaced())
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 420, height: 340)
    }
}

private struct ForwardingStatusRow: View {
    let fwd: PortForwarding

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.green).frame(width: 8, height: 8)
            Image(systemName: iconName).foregroundStyle(.secondary)

            Group {
                switch fwd.type {
                case .local:
                    Text("localhost:\(fwd.localPort) → \(fwd.remoteHost):\(fwd.remotePort)")
                case .remote:
                    Text("remote:\(fwd.remotePort) → localhost:\(fwd.localPort)")
                case .dynamic:
                    Text("SOCKS5 → localhost:\(fwd.localPort)")
                }
            }
            .font(.callout.monospaced())

            if !fwd.description.isEmpty {
                Text("(\(fwd.description))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconName: String {
        switch fwd.type {
        case .local:   return "arrow.down.right.circle"
        case .remote:  return "arrow.up.left.circle"
        case .dynamic: return "globe"
        }
    }
}

// MARK: - RDP Section (placeholder for Feature 8)

struct RDPSection: View {
    @Binding var draft: Session

    var body: some View {
        Section("session.rdp") {
            LabeledContent("session.username") {
                TextField("", text: $draft.rdpUsername)
            }
            LabeledContent("rdp.domain") {
                TextField("", text: $draft.rdpDomain)
            }
            LabeledContent("rdp.resolution") {
                HStack {
                    TextField("", value: $draft.rdpWidth, format: .number).frame(width: 70)
                    Text("×")
                    TextField("", value: $draft.rdpHeight, format: .number).frame(width: 70)
                }
            }
            LabeledContent("rdp.color_depth") {
                Picker("", selection: $draft.rdpColorDepth) {
                    Text("16-bit").tag(16)
                    Text("24-bit").tag(24)
                    Text("32-bit").tag(32)
                }
            }
            Toggle("rdp.fullscreen", isOn: $draft.rdpFullscreen)
            Toggle("rdp.clipboard", isOn: $draft.rdpClipboardSharing)
            Toggle("rdp.drives", isOn: $draft.rdpDriveRedirection)
        }
    }
}
