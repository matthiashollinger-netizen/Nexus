import SwiftUI

struct MasterPasswordView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var password = ""
    @State private var isFirstSetup = false
    @State private var confirmPassword = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("masterpassword.title")
                .font(.title2)
                .fontWeight(.semibold)

            if isFirstSetup {
                Text("masterpassword.setup_hint")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                SecureField("masterpassword.placeholder", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .focused($focused)
                    .onSubmit { unlock() }

                if isFirstSetup {
                    SecureField("masterpassword.confirm", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .onSubmit { unlock() }
                }
            }

            if let error = vm.unlockError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack(spacing: 12) {
                Button("masterpassword.skip") {
                    vm.isUnlocked = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("masterpassword.unlock") {
                    unlock()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(40)
        .frame(width: 440)
        .onAppear {
            focused = true
            // First setup if credentials don't exist yet
            isFirstSetup = !FileManager.default.fileExists(
                atPath: AppViewModel().db.appSupportURL
                    .appendingPathComponent("credentials.enc").path
            )
        }
    }

    private func unlock() {
        if isFirstSetup {
            guard !password.isEmpty && password == confirmPassword else {
                vm.unlockError = String(localized: "masterpassword.mismatch")
                return
            }
            vm.masterPassword = password
            vm.settings.masterPasswordEnabled = true
            vm.saveSettings()
            vm.isUnlocked = true
        } else {
            vm.unlock(password: password)
        }
    }
}
