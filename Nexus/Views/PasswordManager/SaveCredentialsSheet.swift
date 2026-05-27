import SwiftUI

/// Compact sheet shown after a successful interactive SSH login (no stored credentials).
/// Pre-fills username from the session — only the password needs to be entered once.
struct SaveCredentialsSheet: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    let cs: ConnectionSession

    @State private var password: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("savecreds.title")
                        .fontWeight(.semibold)
                    Text(cs.session.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                Section {
                    // Username is read-only — taken from session
                    LabeledContent("cred.username") {
                        Text(cs.session.username.isEmpty ? "-" : cs.session.username)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("cred.password") {
                        SecureField("", text: $password)
                            .focused($focused)
                    }
                } footer: {
                    Text("savecreds.hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(height: 150)

            Divider()

            HStack {
                Button("action.cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("savecreds.save_and_link") {
                    saveCredential()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()
        }
        .frame(width: 380)
        .onAppear {
            // Pre-fill with password captured from terminal input
            if !cs.capturedPassword.isEmpty {
                password = cs.capturedPassword
            }
            focused = true
        }
    }

    private func saveCredential() {
        var cred = Credential()
        cred.name = cs.session.name.isEmpty ? cs.session.host : cs.session.name
        cred.username = cs.session.username
        cred.password = password
        cred.isGroup = false    // session-specific, not shown in group picker

        // Deduplicate
        if let existing = vm.credentials.first(where: {
            $0.username == cred.username && $0.password == cred.password
        }) {
            var updatedSession = cs.session
            updatedSession.credentialId = existing.id
            vm.updateSession(updatedSession)
        } else {
            vm.addCredential(cred)
            var updatedSession = cs.session
            updatedSession.credentialId = cred.id
            vm.updateSession(updatedSession)
        }
        dismiss()
    }
}
