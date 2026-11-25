import SwiftUI

/// Collects and validates an existing wallet's recovery words for import.
struct ImportWalletScreen: View {
    @Environment(\.canDisplayRecovery) private var canDisplayRecovery
    @State private var input = RecoveryEntryModel()
    @FocusState private var focusedField: RecoveryEntryModel.Field?
    let submission: any ImportSubmitting

    var body: some View {
        Form {
            Section {
                TitleCardContent(
                    title: "Import Wallet",
                    message: "Enter or paste your recovery words to restore your wallet.",
                    systemImage: "wallet.bifold.fill"
                )
            }

            Section {
                RecoveryPhraseEntry(input: input, focusedField: $focusedField)
                    .disabled(submission.isPending)

                if let message = input.rejection?.message(in: input.phrase) {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.warning)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            } header: {
                Text("Recovery Words")
            } footer: {
                Text("Neither this app nor iCloud can recover your words.")
            }

            Section {
                RecoveryPassphraseEntry(input: input, focusedField: $focusedField)
                    .disabled(submission.isPending)
            } header: {
                Text("BIP-39 Passphrase (Optional)")
            } footer: {
                Text("A different passphrase opens a different wallet.")
            }
        }
        .animation(.default, value: input.rejection)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .writingToolsBehavior(.disabled)
        .privacySensitive()
        .opacity(canDisplayRecovery ? 1 : 0)
        .accessibilityHidden(!canDisplayRecovery)
        .allowsHitTesting(canDisplayRecovery)
        .overlay {
            if !canDisplayRecovery {
                Text("Recovery input hidden")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .confirmationAction("Import Wallet", isEnabled: input.hasPhrase && canDisplayRecovery,
                            isPending: submission.isPending, action: submit)
        .navigationTitle("Import Wallet")
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: focusedField?.rawValue ?? 0) { oldValue, newValue in
            let oldField = RecoveryEntryModel.Field(rawValue: oldValue)
            let newField = RecoveryEntryModel.Field(rawValue: newValue)
            if oldField == input.phraseField || oldField == .revealedPhrase,
               newField?.isPhrase != true, input.hasPhrase, canDisplayRecovery {
                input.validate()
            }
        }
        .onChange(of: canDisplayRecovery) {
            if !canDisplayRecovery {
                focusedField = nil
                input.showsWords = false
                input.showsPassphrase = false
            }
        }
        .onDisappear {
            focusedField = nil
            input.clear()
        }
    }

    /// Submits valid recovery words for import.
    private func submit() {
        guard canDisplayRecovery else { return }
        focusedField = nil
        guard input.validate() else { return }
        submission.submit(input.phrase, passphrase: input.passphrase)
    }
}
