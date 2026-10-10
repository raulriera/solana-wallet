import SwiftUI
import Wallet

/// Shows one wallet's backup for writing down, or explains that this device no longer has it.
struct RecoveryBackupScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.canDisplayRecovery) private var canDisplayRecovery
    let display: RecoveryDisplay
    let flow: SecurityFlow

    var body: some View {
        Group {
            switch display {
            case .backup(let backup):
                Form {
                    Section {
                        RecoveryWords(phrase: backup.phrase)
                        CopyWordsButton(phrase: backup.phrase, pasteboard: flow.pasteboard)
                    } header: {
                        Text("Recovery Words")
                            .foregroundStyle(palette.secondaryText)
                    } footer: {
                        Text("Write down these words in order and keep them somewhere safe. Anyone with them can control your wallet. Copied words stay on this device and clear from the clipboard after \(flow.pasteboard.lifetime, format: .units(allowed: [.minutes, .seconds], width: .wide)).")
                            .foregroundStyle(palette.secondaryText)
                    }
                    .listRowBackground(palette.surface)

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
                            .foregroundStyle(palette.secondaryText)
                    }
                    .foregroundStyle(palette.primaryText, palette.secondaryText)
                    .listRowBackground(palette.surface)
                    .listRowSeparatorTint(palette.separator)
                }
            case .unavailable:
                ContentUnavailableView {
                    Label("Recovery Phrase Unavailable", systemImage: "key.slash")
                } description: {
                    Text("This device no longer has this wallet's recovery phrase. Reset the app and import your written backup.")
                } actions: {
                    Button("Reset App", systemImage: "trash", role: .destructive) { flow.startReset(.recoveryUnavailable) }
                        .labelStyle(.warning)
                }
                .foregroundStyle(palette.primaryText, palette.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle("Recovery Phrase")
        .navigationBarTitleDisplayMode(.inline)
    }
}
