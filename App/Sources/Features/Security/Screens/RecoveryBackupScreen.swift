import SwiftUI
import Wallet

/// Shows a wallet's recovery backup, or explains that it isn't on this device.
struct RecoveryBackupScreen: View {
    @Environment(\.canDisplayRecovery) private var canDisplayRecovery
    let display: RecoveryDisplay
    let coordinator: SecurityCoordinator

    var body: some View {
        Group {
            switch display {
            case .backup(let backup):
                Form {
                    Section {
                        RecoveryWords(phrase: backup.phrase)
                        CopyWordsButton(phrase: backup.phrase, pasteboard: coordinator.pasteboard)
                    } header: {
                        Text("Recovery Words")
                    } footer: {
                        Text("Write down these words in order and keep them somewhere safe. Anyone with them can control your wallet. Copied words stay on this device and clear from the clipboard after \(coordinator.pasteboard.lifetime, format: .units(allowed: [.minutes, .seconds], width: .wide)).")
                    }

                    Section {
                        if !backup.passphrase.isEmpty {
                            LabeledContent("BIP-39 Passphrase") {
                                (canDisplayRecovery ? Text(backup.passphrase, format: .passphrase) : Text("Hidden"))
                                    .accessibilityLabel(canDisplayRecovery ? Text(backup.passphrase, format: .spokenPassphrase) : Text("Hidden"))
                                    .privacySensitive()
                            }
                        }
                        LabeledContent("Account Path") {
                            Text(verbatim: backup.path.description)
                        }
                    } footer: {
                        Text("You need these details with your words to restore this wallet.")
                    }
                }
            case .unavailable:
                UnavailableScreen(title: "Recovery Phrase Unavailable",
                                  message: "This device no longer has this wallet's recovery phrase. Reset the app and import your written backup.",
                                  systemImage: "key.slash") {
                    Button("Reset App", role: .destructive) { coordinator.startReset(.recoveryUnavailable) }
                        .buttonStyle(.destructive)
                }
            }
        }
        .navigationTitle("Recovery Phrase")
        .toolbarTitleDisplayMode(.inline)
    }
}
