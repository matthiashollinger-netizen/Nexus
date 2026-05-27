import SwiftUI

struct MasterPasswordView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var saveToKeychain = true
    @State private var syncToiCloud = false
    @State private var isFirstSetup = false
    @State private var keychainError: String? = nil
    @State private var showResetConfirm = false
    @State private var failedAttempts = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text(isFirstSetup ? String(localized: "masterpassword.setup_title") : String(localized: "masterpassword.title"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(isFirstSetup ? String(localized: "masterpassword.setup_hint") : String(localized: "masterpassword.enter_hint"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            VStack(spacing: 10) {
                SecureField(String(localized: "masterpassword.placeholder"), text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .focused($focused)

                if isFirstSetup {
                    SecureField(String(localized: "masterpassword.confirm"), text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)

                    Divider().frame(width: 300)

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(String(localized: "masterpassword.save_keychain"), isOn: $saveToKeychain)
                        if saveToKeychain {
                            Toggle(String(localized: "masterpassword.sync_icloud"), isOn: $syncToiCloud)
                                .padding(.leading, 20)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 300)
                    .font(.callout)
                } else {
                    // Offer to save to Keychain if not already stored
                    if !KeychainService.hasMasterPasswordInKeychain {
                        Toggle(String(localized: "masterpassword.save_keychain"), isOn: $saveToKeychain)
                            .frame(width: 300)
                            .font(.callout)
                    }
                }
            }

            // Error messages
            if let error = vm.unlockError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                }
                .foregroundStyle(.red)
                .font(.callout)
            }
            if let kErr = keychainError {
                HStack(spacing: 4) {
                    Image(systemName: "key.slash")
                    Text(kErr)
                }
                .foregroundStyle(.orange)
                .font(.caption)
                .frame(maxWidth: 300)
                .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                if !isFirstSetup {
                    Button(String(localized: "masterpassword.skip")) {
                        vm.isUnlocked = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Button(isFirstSetup ? String(localized: "masterpassword.setup_btn") : String(localized: "masterpassword.unlock")) {
                    unlock()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }

            // Reset option — shown after 2 failed attempts or always in non-first-setup if unlockError is set
            if !isFirstSetup && failedAttempts >= 2 {
                Divider().frame(width: 300)
                VStack(spacing: 6) {
                    Text("masterpassword.reset_hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    Button(String(localized: "masterpassword.reset_btn")) {
                        showResetConfirm = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.callout)
                }
            }
        }
        .padding(40)
        .frame(width: 460)
        .onAppear {
            let encFile = vm.db.appSupportURL.appendingPathComponent("credentials.enc")
            isFirstSetup = !FileManager.default.fileExists(atPath: encFile.path)

            // Auto-unlock from Keychain
            if !isFirstSetup, let stored = KeychainService.loadMasterPassword() {
                vm.unlock(password: stored)
            } else {
                focused = true
            }
        }
        .confirmationDialog(
            String(localized: "masterpassword.reset_confirm_title"),
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "masterpassword.reset_confirm_btn"), role: .destructive) {
                resetAll()
            }
            Button(String(localized: "action.cancel"), role: .cancel) {}
        } message: {
            Text("masterpassword.reset_confirm_msg")
        }
    }

    private func unlock() {
        keychainError = nil
        if isFirstSetup {
            guard password == confirmPassword else {
                vm.unlockError = String(localized: "masterpassword.mismatch")
                return
            }
            if saveToKeychain {
                do {
                    try KeychainService.saveMasterPassword(password, syncToiCloud: syncToiCloud)
                } catch {
                    keychainError = error.localizedDescription
                }
            }
            vm.masterPassword = password
            vm.settings.masterPasswordEnabled = true
            vm.saveSettings()
            try? vm.db.saveCredentials([], masterPassword: password)
            vm.isUnlocked = true
        } else {
            vm.unlock(password: password)
            if vm.isUnlocked {
                if saveToKeychain && !KeychainService.hasMasterPasswordInKeychain {
                    do {
                        try KeychainService.saveMasterPassword(password, syncToiCloud: syncToiCloud)
                    } catch {
                        keychainError = error.localizedDescription
                    }
                }
            } else {
                failedAttempts += 1
            }
        }
    }

    private func resetAll() {
        // Delete encrypted credentials file
        let encFile = vm.db.appSupportURL.appendingPathComponent("credentials.enc")
        try? FileManager.default.removeItem(at: encFile)
        // Clear keychain
        KeychainService.deleteMasterPassword()
        // Reset app state — now opens without encryption
        vm.masterPassword = ""
        vm.unlockError = nil
        vm.credentials = []
        vm.settings.masterPasswordEnabled = false
        vm.saveSettings()
        vm.isUnlocked = true
    }
}
