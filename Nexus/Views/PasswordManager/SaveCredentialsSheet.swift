import SwiftUI

/// Sheet shown after a successful interactive SSH login (no stored credentials).
/// Gives the user the chance to save their credentials to the password manager.
struct SaveCredentialsSheet: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    let cs: ConnectionSession

    @State private var name: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var saveEnabled = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "key.badge.plus")
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
                    LabeledContent("cred.name") {
                        TextField("savecreds.name_placeholder", text: $name)
                    }
                    LabeledContent("cred.username") {
                        TextField("session.username.placeholder", text: $username)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("cred.password") {
                        SecureField("cred.password.placeholder", text: $password)
                    }
                } footer: {
                    Text("savecreds.hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

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
                .disabled(username.isEmpty || password.isEmpty)
            }
            .padding()
        }
        .frame(width: 400)
        .onAppear {
            username = cs.session.username
            name = cs.session.name.isEmpty ? cs.session.host : cs.session.name
        }
    }

    private func saveCredential() {
        var cred = Credential()
        cred.name = name.isEmpty ? cs.session.host : name
        cred.username = username
        cred.password = password

        vm.addCredential(cred)

        // Link to session
        var updatedSession = cs.session
        updatedSession.credentialId = cred.id
        vm.updateSession(updatedSession)

        dismiss()
    }
}
