import SwiftUI

/// Lists automatic backups and lets the user restore or delete them.
/// Backups are created at app launch and (throttled) before saves — see
/// DatabaseService.createBackup.
struct BackupManagerView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    @State private var backups: [BackupInfo] = []
    @State private var restoreTarget: BackupInfo? = nil
    @State private var statusMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.backups.title").font(.headline)
                    Text("settings.backups.subtitle").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("action.close") { dismiss() }
            }
            .padding()

            Divider()

            if backups.isEmpty {
                ContentUnavailableView(
                    "settings.backups.empty",
                    systemImage: "clock.badge.questionmark",
                    description: Text("settings.backups.empty_hint")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(backups) { backup in
                        BackupRow(backup: backup,
                                  onRestore: { restoreTarget = backup },
                                  onDelete: { delete(backup) })
                    }
                }
            }

            if let status = statusMessage {
                Divider()
                Label(status, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(8)
            }

            Divider()

            HStack {
                Button("settings.backups.create_now") {
                    if vm.db.createBackup(force: true) != nil {
                        statusMessage = String(localized: "settings.backups.created")
                        reload()
                    }
                }
                Spacer()
                Text("settings.backups.count \(backups.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(width: 520, height: 460)
        .onAppear { reload() }
        .confirmationDialog(
            "settings.backups.restore_confirm",
            isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("settings.backups.restore", role: .destructive) {
                if let target = restoreTarget { restore(target) }
                restoreTarget = nil
            }
            Button("action.cancel", role: .cancel) { restoreTarget = nil }
        } message: {
            Text("settings.backups.restore_message")
        }
    }

    private func reload() {
        backups = vm.db.listBackups()
    }

    private func restore(_ backup: BackupInfo) {
        do {
            try vm.db.restoreBackup(from: backup.url)
            vm.loadData()           // reload sessions/folders/settings into the live VM
            statusMessage = String(localized: "settings.backups.restored")
            reload()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func delete(_ backup: BackupInfo) {
        vm.db.deleteBackup(backup.url)
        reload()
    }
}

private struct BackupRow: View {
    let backup: BackupInfo
    let onRestore: () -> Void
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.zipper")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateFormatter.string(from: backup.createdAt))
                    .font(.callout)
                Text("settings.backups.row_detail \(backup.sessionCount) \(formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("settings.backups.restore") { onRestore() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(backup.sizeBytes), countStyle: .file)
    }
}
