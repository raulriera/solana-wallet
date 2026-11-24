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
            "Resetting deletes every wallet on this device. Only your written recovery phrase can restore them."
        case .recoveryUnavailable:
            "Resetting deletes every wallet on this device."
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
                    Text("Back up your recovery phrase before you continue.")
                }
            }

            Section {
                Button("Continue") { coordinator.confirmReset() }
                    .tint(palette.destructive)
            }
        }
        .navigationTitle("Reset App")
        .toolbarTitleDisplayMode(.inline)
    }
}
