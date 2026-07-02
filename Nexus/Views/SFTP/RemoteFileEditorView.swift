import SwiftUI
import AppKit

// MARK: - Remote file editor
//
// Opens a text file from the SFTP browser in the integrated editor (same
// NSTextView + syntax highlighting as the standalone editor). Editing and
// "Save & upload" write the file back to the server via sftp `put`.

struct RemoteFileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let fileName: String
    let remotePath: String
    let conn: SFTPConnection

    @State private var content: String
    @State private var fontSize: Double = 13
    @State private var isSaving = false
    @State private var status: LocalizedStringKey? = nil
    @State private var isError = false

    init(fileName: String, remotePath: String, conn: SFTPConnection, initialContent: String) {
        self.fileName = fileName
        self.remotePath = remotePath
        self.conn = conn
        _content = State(initialValue: initialContent)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                IconBadge(systemImage: "doc.text", pointSize: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(fileName).font(DS.Font.headline)
                    MonoText(remotePath)
                }
                Spacer()
                if let status {
                    Text(status).font(DS.Font.caption)
                        .foregroundStyle(isError ? DS.Color.stateFailed : DS.Color.stateConnected)
                }
                Button { Task { await save() } } label: {
                    Label("editor.save_upload", systemImage: "arrow.up.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
                .keyboardShortcut("s", modifiers: .command)
                Button("action.close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(DS.Space.md)

            Divider()

            NexusCodeEditorView(
                text: Binding(get: { content }, set: { content = $0; status = nil }),
                fontSize: fontSize,
                filePath: fileName
            )
        }
        .frame(width: 780, height: 560)
    }

    private func save() async {
        isSaving = true
        status = nil
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nexus_edit_\(UUID().uuidString)_\(fileName)")
        // Guarantee the local temp copy is removed even if the upload throws.
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try content.write(to: tmp, atomically: true, encoding: .utf8)
            try await SFTPService.shared.uploadFile(conn, from: tmp, remotePath: remotePath)
            status = "editor.saved"
            isError = false
        } catch {
            status = LocalizedStringKey(error.localizedDescription)
            isError = true
        }
        isSaving = false
    }
}
