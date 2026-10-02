import SwiftUI
import Wallet

/// Presents a prepared recovery phrase for backup without generating or storing it.
struct RecoveryPhraseScreen: View {
    @Environment(\.palette) private var palette
    @State private var contentInset: CGFloat = 16
    @State private var isConfirmingBackup = false
    let phrase: RecoveryPhrase
    let continueSetup: () -> Void

    var body: some View {
        Form {
            Section {
                Text(
                    "Write down these words in order and keep them somewhere safe. Anyone with them can control your wallet."
                )
                .foregroundStyle(palette.primaryText)
            }
            .listRowBackground(palette.surface)

            Section {
                RecoveryWords(phrase: phrase)
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
            Button {
                isConfirmingBackup = true
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(palette.primaryText)
            .foregroundStyle(palette.background)
            .padding(.horizontal, contentInset)
            .padding(.vertical, 8)
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
    }
}

#Preview("Public test phrase") {
    if let phrase = try? RecoveryPhrase(
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
    {
        NavigationStack {
            RecoveryPhraseScreen(phrase: phrase, continueSetup: {})
        }
        .tint(RenderedPalette(OriginalAppearance.palette).accent)
    }
}
