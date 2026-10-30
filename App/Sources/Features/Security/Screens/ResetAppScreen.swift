import SwiftUI

/// Explains what a reset deletes before the final confirmation.
struct ResetAppScreen: View {
    @Environment(\.palette) private var palette
    let mode: ResetMode
    let account: Account
    let coordinator: SecurityCoordinator

    private var message: LocalizedStringResource {
        switch mode {
        case .standard:
            "Resetting deletes every wallet, recovery phrase, theme, your RPC API key, and custom RPCs from this device. Every window returns to Welcome. Only your written recovery phrase can restore your wallets."
        case .recoveryUnavailable:
            "This device no longer has your wallet's recovery phrase, so resetting is the only fix. Resetting deletes every wallet, your RPC API key, and custom RPCs from this device. Every window returns to Welcome. Then import your written backup."
        }
    }

    var body: some View {
        Form {
            Section {} footer: {
                Text(message)
                    .foregroundStyle(palette.secondaryText)
            }

            if mode == .standard {
                Section {
                    Button("Show Recovery Phrase") { coordinator.showRecovery(for: account) }
                        .foregroundStyle(palette.accent)
                } footer: {
                    Text("Make sure you've written down your recovery phrase before you continue.")
                        .foregroundStyle(palette.secondaryText)
                }
                .listRowBackground(palette.surface)
            }

            Section {
                Button("Continue") { coordinator.confirmReset() }
                    .foregroundStyle(palette.accent)
            }
            .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .navigationTitle("Reset App")
        .navigationBarTitleDisplayMode(.inline)
    }
}
