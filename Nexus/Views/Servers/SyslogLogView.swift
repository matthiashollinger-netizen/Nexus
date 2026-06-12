import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Live Syslog viewer
//
// The structured, filterable log a network engineer watches while a switch boots
// or a firmware push runs. Severity is color-coded (error+ red, warning amber,
// the rest calm), with a free-text filter, a severity floor, an alert counter and
// CSV export. Reads the @Observable NativeSyslogServer's ring buffer live.

struct SyslogLogView: View {
    let server: NativeSyslogServer

    @State private var filterText = ""
    @State private var minSeverity: SyslogSeverity = .debug   // show everything by default
    @State private var autoScroll = true

    private var filtered: [SyslogEntry] {
        server.entries.filter { entry in
            entry.severity.rawValue <= minSeverity.rawValue &&
            (filterText.isEmpty ||
             entry.message.localizedCaseInsensitiveContains(filterText) ||
             entry.sourceIP.contains(filterText) ||
             entry.tag.localizedCaseInsensitiveContains(filterText) ||
             entry.hostname.localizedCaseInsensitiveContains(filterText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            logList
        }
        .background(DS.Color.surface)
    }

    private var controls: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
            TextField("syslog.filter.placeholder", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Picker("", selection: $minSeverity) {
                ForEach(SyslogSeverity.allCases) { sev in
                    Text(sev.keyword).tag(sev)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            .help("syslog.severity.floor")

            if server.alertCount > 0 {
                Label("\(server.alertCount)", systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.stateFailed)
                    .help("syslog.alerts")
            }

            Spacer()

            Text("\(filtered.count)")
                .font(DS.Font.mono).foregroundStyle(.secondary)
            Button { exportCSV() } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.borderless).help("syslog.export")
            Button { server.clear() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("syslog.clear")
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        emptyHint
                    } else {
                        ForEach(filtered) { entry in
                            SyslogRow(entry: entry).id(entry.id)
                        }
                    }
                }
            }
            .onChange(of: server.entries.count) { _, _ in
                guard autoScroll, let last = filtered.last else { return }
                withAnimation(DS.Motion.quick) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: DS.Space.sm) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 28)).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
            Text("syslog.waiting.title").font(DS.Font.callout)
            Text("syslog.waiting.hint").font(DS.Font.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xxxl)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "syslog.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? server.exportCSV(to: url)
    }
}

// MARK: - One syslog row

private struct SyslogRow: View {
    let entry: SyslogEntry

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Text(entry.severity.keyword)
                .font(DS.Font.caption.weight(.semibold))
                .foregroundStyle(entry.severity.color)
                .frame(width: 54, alignment: .leading)
            MonoText(Self.time.string(from: entry.receivedAt))
                .frame(width: 64, alignment: .leading)
            MonoText(entry.sourceIP, tint: DS.Color.textSecondary)
                .frame(width: 104, alignment: .leading)
            if !entry.tag.isEmpty {
                Text(entry.tag)
                    .font(DS.Font.caption).foregroundStyle(DS.Color.accent)
                    .lineLimit(1)
            }
            Text(entry.message)
                .font(DS.Font.mono)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, 3)
        .background(entry.severity.isAlert ? entry.severity.color.opacity(0.06) : .clear)
        .contextMenu {
            Button("action.copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.message, forType: .string)
            }
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}
