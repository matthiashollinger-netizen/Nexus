import SwiftUI

struct OnboardingView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon + title
            VStack(spacing: 16) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.accentColor)

                Text("onboarding.title")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("onboarding.subtitle")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Spacer()

            // Encryption option card
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("onboarding.encryption.title")
                            .fontWeight(.semibold)
                        Text("onboarding.encryption.hint")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxWidth: 460)

            Spacer().frame(height: 32)

            // Action buttons
            HStack(spacing: 20) {
                Button("onboarding.skip") {
                    complete(enableEncryption: false)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("onboarding.setup_encryption") {
                    complete(enableEncryption: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer().frame(height: 48)
        }
        .frame(width: 560, height: 460)
    }

    private func complete(enableEncryption: Bool) {
        vm.settings.hasCompletedOnboarding = true
        if enableEncryption {
            vm.settings.masterPasswordEnabled = true
            // isUnlocked was set to true at init (when encryption was off).
            // Reset it so ContentView transitions to MasterPasswordView.
            vm.isUnlocked = false
        }
        vm.saveSettings()
    }
}
