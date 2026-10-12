import SwiftUI

/// Collects and validates existing recovery without deriving accounts or saving secrets.
struct ImportWalletScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.canDisplayRecovery) private var canDisplayRecovery
    @State private var input: RecoveryInput
    @State private var contentInset = LayoutMetrics.contentMargin
    @FocusState private var focusedField: RecoveryInput.Field?
    private let submission: any ImportSubmitting

    /// Creates an entry screen with an optional one-time seed for public-fixture previews.
    /// - Parameters:
    ///   - initialPhrase: Initial input, empty for normal wallet imports; later values never replace edits.
    ///   - submission: Receives locally validated input after explicit approval; owns subsequent work.
    init(initialPhrase: String = "", submission: any ImportSubmitting) {
        input = RecoveryInput(phrase: initialPhrase)
        self.submission = submission
    }

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

                if let validationMessage = input.validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.circle.fill")
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
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .readableContentMargins(inset: $contentInset)
        .safeAreaBar(edge: .bottom) {
            Button("Import Wallet", action: submit)
                .buttonStyle(.primary(isPending: submission.isPending))
                .disabled(!input.hasPhrase || !canDisplayRecovery || submission.isPending)
                .padding(.horizontal, contentInset)
                .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle("Import Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focusedField?.rawValue ?? 0) { oldValue, newValue in
            // Replacing the phrase control also resigns its focus; that isn't an editing exit.
            let oldField = RecoveryInput.Field(rawValue: oldValue)
            let newField = RecoveryInput.Field(rawValue: newValue)
            if oldField == input.phraseField,
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

#Preview("Public import fixture") {
    NavigationStack {
        ImportWalletScreen(
            initialPhrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            submission: PreviewImportSubmission()
        )
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

/// Keeps public-fixture previews local without persistence or task side effects.
private struct PreviewImportSubmission: ImportSubmitting {
    var isPending: Bool { false }

    /// Accepts preview interaction without retaining or saving its supplied input.
    /// - Parameters:
    ///   - phrase: The preview's recovery input.
    ///   - passphrase: The preview's optional original passphrase.
    func submit(_ phrase: String, passphrase: String) {}
}
