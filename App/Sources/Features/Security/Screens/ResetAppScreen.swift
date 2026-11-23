import SwiftUI

/// Explains what a reset deletes before the final confirmation.
struct ResetAppScreen: View {
    let mode: ResetMode
    let account: Account
    let coordinator: SecurityCoordinator

    private var message: LocalizedStringResource {
        switch mode {
        case .standard:
            "Resetting deletes everything this app saved on this device, including every wallet and recovery phrase. Every window returns to Welcome. Only your written recovery phrase can restore your wallets."
        case .recoveryUnavailable:
            "This device no longer has your wallet's recovery phrase, so resetting is the only fix. Resetting deletes everything this app saved on this device, including every wallet. Every window returns to Welcome. Then import your written backup."
        }
    }

    var body: some View {
        Form {
            Section {} footer: {
                Text(message)
            }

            if mode == .standard {
                Section {
                    Button("Show Recovery Phrase") { coordinator.showRecovery(for: account) }
                } footer: {
                    Text("Make sure you've written down your recovery phrase before you continue.")
                }
            }

            Section {
                Button("Continue") { coordinator.confirmReset() }
            }
        }
        .navigationTitle("Reset App")
        .toolbarTitleDisplayMode(.inline)
    }
}
