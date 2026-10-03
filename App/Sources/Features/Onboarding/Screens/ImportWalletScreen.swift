import SwiftUI
import Wallet

/// Collects and validates existing recovery without deriving accounts or saving secrets.
struct ImportWalletScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @State private var phrase: String
    @State private var passphrase = ""
    @State private var showsWords = false
    @State private var validationError: RecoveryPhrase.ValidationError?
    @State private var contentInset = LayoutMetrics.contentMargin
    @FocusState private var focusedField: Field?
    private let importWallet: (_ phrase: String, _ passphrase: String) -> Void

    /// Identifies native input controls without putting recovery text in navigation state.
    private enum Field: Hashable {
        case hiddenPhrase, revealedPhrase, passphrase

        var isPhrase: Bool { self != .passphrase }
    }

    private var canDisplayRecovery: Bool { scenePhase == .active && !isSceneCaptured }
    private var hasPhrase: Bool { phrase.contains { !$0.isWhitespace } }

    /// Creates an entry screen with an optional one-time seed for public-fixture previews.
    /// - Parameters:
    ///   - initialPhrase: Initial input, empty for normal wallet imports; later values never replace edits.
    ///   - importWallet: Receives locally validated input after explicit approval; owns subsequent work.
    init(initialPhrase: String = "", importWallet: @escaping (_ phrase: String, _ passphrase: String) -> Void) {
        self.phrase = initialPhrase
        self.importWallet = importWallet
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "wallet.bifold.fill")
                        .font(.largeTitle)
                        .foregroundStyle(palette.accent)
                        .padding(.bottom, 8)
                        .accessibilityHidden(true)

                    Text("Import Wallet")
                        .font(.title2.bold())
                        .foregroundStyle(palette.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text("Enter or paste your recovery words to restore your wallet.")
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(palette.surface)

            Section {
                if showsWords {
                    TextField("Recovery words", text: $phrase, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .revealedPhrase)
                        .transition(.opacity)
                } else {
                    SecureField("Recovery words", text: $phrase)
                        .focused($focusedField, equals: .hiddenPhrase)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .passphrase }
                        .transition(.opacity)
                }

                Button(showsWords ? "Hide words" : "Show words", action: toggleWords)
                    .contentTransition(.opacity)

                if let validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            } header: {
                Text("Recovery Words")
                    .foregroundStyle(palette.secondaryText)
            } footer: {
                Text("Use your recovery words in their original order, separated by spaces. Keep your original words and any BIP-39 passphrase safe. Neither this app nor iCloud can recover them. You'll need your backup if you lose this device or change its enrolled biometrics.")
                    .foregroundStyle(palette.secondaryText)
            }
            .foregroundStyle(palette.primaryText)
            .listRowBackground(palette.surface)

            Section {
                SecureField("Optional", text: $passphrase)
                    .foregroundStyle(palette.primaryText)
                    .accessibilityLabel("BIP-39 passphrase, optional")
                    .focused($focusedField, equals: .passphrase)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
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
                .buttonStyle(.primary)
                .disabled(!hasPhrase || !canDisplayRecovery)
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
        .onChange(of: phrase) { withAnimation { validationError = nil } }
        .onChange(of: focusedField) { oldField, newField in
            // Replacing the phrase control also resigns its focus; that isn't an editing exit.
            if oldField == (showsWords ? .revealedPhrase : .hiddenPhrase),
               newField?.isPhrase != true, hasPhrase, canDisplayRecovery {
                _ = validatePhrase()
            }
        }
        .onChange(of: canDisplayRecovery) {
            if !canDisplayRecovery {
                focusedField = nil
                showsWords = false
            }
        }
        .onDisappear {
            focusedField = nil
            phrase = ""
            passphrase = ""
            validationError = nil
            showsWords = false
        }
    }

    /// A local-only explanation; an unknown word is shown here and never logged.
    private var validationMessage: String? {
        switch validationError {
        case .invalidWordCount:
            return String(localized: "Enter at least 12 recovery words.")
        case .unknownWord(let position):
            let words = phrase.decomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace)
            guard words.indices.contains(position) else { return nil }
            return String(localized: "‘\(words[position])’ isn't a valid recovery word.")
        case .invalidChecksum, .invalidEntropy:
            return String(localized: "These words don't form a valid recovery phrase. Check their spelling and order.")
        case nil:
            return nil
        }
    }

    /// Switches native controls while preserving input and the user's editing focus.
    private func toggleWords() {
        let wasEditingPhrase = focusedField?.isPhrase == true
        withAnimation {
            showsWords.toggle()
            if wasEditingPhrase { focusedField = showsWords ? .revealedPhrase : .hiddenPhrase }
        }
    }

    /// Checks the existing BIP-39 validator without retaining an additional recovery value.
    /// - Returns: Whether word count, English words, and checksum are all valid.
    private func validatePhrase() -> Bool {
        withAnimation {
            do {
                _ = try RecoveryPhrase(phrase)
                validationError = nil
                return true
            } catch let error as RecoveryPhrase.ValidationError {
                validationError = error
            } catch {
                validationError = .invalidEntropy
            }
            return false
        }
    }

    /// Delegates only a valid phrase, preserving the original passphrase exactly.
    private func submit() {
        guard canDisplayRecovery else { return }
        focusedField = nil
        guard validatePhrase() else { return }
        importWallet(phrase, passphrase)
    }
}

#Preview("Public import fixture") {
    NavigationStack {
        ImportWalletScreen(
            initialPhrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            importWallet: { _, _ in }
        )
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}
