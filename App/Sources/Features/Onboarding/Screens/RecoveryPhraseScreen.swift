import SwiftUI
import Wallet

/// Presents a prepared recovery phrase for backup without generating or storing it.
struct RecoveryPhraseScreen: View {
    @Environment(\.palette) private var palette
    @State private var contentInset = LayoutMetrics.contentMargin
    @State private var isConfirmingBackup = false
    @State private var phrase: RecoveryPhrase?
    let isSaved: Bool
    let continueSetup: () -> Void

    /// Shows the words it opened with until the wallet is saved and the next step covers this screen.
    /// - Parameters:
    ///   - initialPhrase: The prepared words when the screen opens; later values are ignored.
    ///   - isSaved: Whether the wallet is saved; its words then leave memory once this screen is covered.
    ///   - continueSetup: Saves the wallet after the user confirms their backup.
    init(initialPhrase: RecoveryPhrase?, isSaved: Bool, continueSetup: @escaping () -> Void) {
        _phrase = State(initialValue: initialPhrase)
        self.isSaved = isSaved
        self.continueSetup = continueSetup
    }

    var body: some View {
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
                if let phrase {
                    RecoveryWords(phrase: phrase)
                }
            } header: {
                Text("Recovery Words")
                    .foregroundStyle(palette.secondaryText)
            } footer: {
                Text(
                    "These words are your only way to restore this wallet. Neither the app nor iCloud can recover them. You'll need them if you lose this device or change its enrolled biometrics."
                )
                .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .readableContentMargins(inset: $contentInset)
        .safeAreaBar(edge: .bottom) {
            Button("Continue") {
                isConfirmingBackup = true
            }
            .buttonStyle(.primary)
            .padding(.horizontal, contentInset)
            .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle("Recovery Phrase")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Have you saved your recovery words?", isPresented: $isConfirmingBackup) {
            Button("Yes", role: .confirm, action: continueSetup)
            Button("No", role: .cancel) {}
        } message: {
            Text("Make sure you've written down all the words in order and stored them somewhere safe.")
        }
        .onDisappear {
            // A saved wallet never returns to its backup, so release the words once they're off screen.
            if isSaved { phrase = nil }
        }
    }
}

#Preview("Public test phrase") {
    if let phrase = try? RecoveryPhrase(
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
    {
        NavigationStack {
            RecoveryPhraseScreen(initialPhrase: phrase, isSaved: false, continueSetup: {})
        }
        .tint(RenderedPalette(OriginalAppearance.palette).accent)
    }
}
