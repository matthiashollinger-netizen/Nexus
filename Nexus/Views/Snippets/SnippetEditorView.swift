import SwiftUI

// MARK: - Snippet Editor
//
// A lightweight sheet to manage a session's reusable command snippets (e.g.
// "show running-config", "show version"). Self-contained — it edits a local copy
// and saves back through vm.updateSession, never touching the large session editor.

struct SnippetEditorView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    let session: Session
    @State private var snippets: [Snippet]

    init(session: Session) {
        self.session = session
        _snippets = State(initialValue: session.snippets)
    }

    private var sessionName: String { session.name.isEmpty ? session.host : session.name }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 520, height: 460)
    }

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            IconBadge(systemImage: "text.append", pointSize: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("snippets.title").font(DS.Font.title)
                Text(sessionName).font(DS.Font.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DS.Space.xl)
    }

    @ViewBuilder private var content: some View {
        if snippets.isEmpty {
            EmptyStateView(
                symbol: "text.append",
                title: "snippets.empty.title",
                message: "snippets.empty.message",
                primary: ("snippets.add", { addSnippet() })
            )
        } else {
            ScrollView {
                VStack(spacing: DS.Space.sm) {
                    ForEach($snippets) { $snippet in
                        SnippetRow(snippet: $snippet) { remove(snippet) }
                    }
                }
                .padding(DS.Space.xl)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button { addSnippet() } label: {
                Label("snippets.add", systemImage: "plus")
            }
            Spacer()
            Button("action.cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("action.save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(DS.Space.lg)
    }

    private func addSnippet() {
        snippets.append(Snippet(title: "", command: ""))
    }

    private func remove(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
    }

    private func save() {
        var updated = session
        // Drop blank snippets so the list stays clean.
        updated.snippets = snippets.filter {
            !$0.command.trimmingCharacters(in: .whitespaces).isEmpty
        }
        vm.updateSession(updated)
        dismiss()
    }
}

// MARK: - Row

private struct SnippetRow: View {
    @Binding var snippet: Snippet
    let onDelete: () -> Void

    var body: some View {
        NexusCard(padding: DS.Space.lg, hoverLift: false) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.sm) {
                    TextField("snippets.field.title", text: $snippet.title)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Font.body)
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("action.delete")
                }
                TextField("snippets.field.command", text: $snippet.command)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Font.mono)
                Toggle("snippets.field.send_return", isOn: $snippet.sendReturn)
                    .font(DS.Font.caption)
                    .toggleStyle(.checkbox)
            }
        }
    }
}
