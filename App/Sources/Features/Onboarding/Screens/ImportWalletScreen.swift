import SwiftUI

/// Collects and validates existing recovery without deriving accounts or saving secrets.
struct ImportWalletScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.canDisplayRecovery) private var canDisplayRecovery
    @State private var input = RecoveryEntryModel()
    @FocusState private var focusedField: RecoveryEntryModel.Field?
    /// Receives locally validated input after explicit approval; owns subsequent work.
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
            .listRowBackground(palette.surface)

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
                    .foregroundStyle(palette.secondaryText)
            } footer: {
                Text("Use your recovery words in their original order, separated by spaces. Keep your original words and any BIP-39 passphrase safe. Neither this app nor iCloud can recover them. You'll need your backup if you lose this device or remove its passcode.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)

            Section {
                RecoveryPassphraseEntry(input: input, focusedField: $focusedField)
                    .disabled(submission.isPending)
            } header: {
                Text("BIP-39 Passphrase (Optional)")
                    .foregroundStyle(palette.secondaryText)
            } footer: {
                Text("Enter this only if your original wallet used one. This is separate from your app password or PIN. Capital letters and spaces matter. A different passphrase opens a different wallet.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
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
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .scrollDismissesKeyboard(.interactively)
        .confirmationAction("Import Wallet", isEnabled: input.hasPhrase && canDisplayRecovery,
                            isPending: submission.isPending, action: submit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle("Import Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focusedField?.rawValue ?? 0) { oldValue, newValue in
            // Revealing the words replaces the hidden control and resigns its focus; that isn't an editing exit.
            // Hiding them while editing ends editing, so it checks the words as leaving the field does.
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

    /// Delegates only a valid phrase, preserving the original passphrase exactly.
    private func submit() {
        guard canDisplayRecovery else { return }
        focusedField = nil
        guard input.validate() else { return }
        submission.submit(input.phrase, passphrase: input.passphrase)
    }
}

#Preview {
    NavigationStack {
        ImportWalletScreen(submission: PreviewImportSubmission())
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

/// Keeps previews local without persistence or task side effects.
private struct PreviewImportSubmission: ImportSubmitting {
    var isPending: Bool { false }

    /// Accepts preview interaction without retaining or saving its supplied input.
    /// - Parameters:
    ///   - phrase: The preview's recovery input.
    ///   - passphrase: The preview's optional original passphrase.
    func submit(_ phrase: String, passphrase: String) {}
}
