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
                        TitleCardContent(
                            title: "Recovery Phrase",
                            message: "Write down these words in order and keep them somewhere safe. Anyone with them can control your wallet.",
                            systemImage: "key.fill"
                        )
                    }
                    .listRowBackground(palette.surface)

                    Section {
                        RecoveryWords(phrase: backup.phrase)
                        CopyWordsButton(phrase: backup.phrase, pasteboard: flow.pasteboard)
                    } header: {
                        Text("Recovery Words")
                            .foregroundStyle(palette.secondaryText)
                    } footer: {
                        Text("Copied words stay on this device and clear from the clipboard after \(flow.pasteboard.lifetime, format: .units(allowed: [.minutes, .seconds], width: .wide)).")
                            .foregroundStyle(palette.secondaryText)
                    }
                    .listRowBackground(palette.surface)

                    Section {
                        if !backup.passphrase.isEmpty {
                            LabeledContent("BIP-39 Passphrase") {
                                Text(verbatim: canDisplayRecovery ? backup.passphrase : String(localized: "Hidden"))
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
                    Button("Reset App", role: .destructive) { flow.startReset(.recoveryUnavailable) }
                        .foregroundStyle(.red)
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
