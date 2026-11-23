import SwiftUI
import Wallet

/// Shows a new recovery phrase for backup.
struct RecoveryPhraseScreen: View {
    @Environment(\.palette) private var palette
    @State private var isConfirmingBackup = false
    @State private var phrase: RecoveryPhrase?
    let isSaved: Bool
    let pasteboard: any RecoveryCopying
    let continueSetup: () -> Void

    /// Creates a recovery phrase screen.
    ///
    /// - Parameters:
    ///   - initialPhrase: The words that the screen shows.
    ///   - isSaved: Whether the wallet is saved.
    ///   - pasteboard: The pasteboard that copies the words.
    ///   - continueSetup: The action that saves the wallet.
    init(initialPhrase: RecoveryPhrase?, isSaved: Bool, pasteboard: any RecoveryCopying,
         continueSetup: @escaping () -> Void) {
        _phrase = State(initialValue: initialPhrase)
        self.isSaved = isSaved
        self.pasteboard = pasteboard
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

            Section {
                if let phrase {
                    RecoveryWords(phrase: phrase)
                }

                CopyWordsButton(phrase: phrase, pasteboard: pasteboard)
            } header: {
                Text("Recovery Words")
            } footer: {
                Text(
                    "These words are your only way to restore this wallet. Neither the app nor iCloud can recover them. You'll need them if you lose this device or remove its passcode. Copied words stay on this device and clear from the clipboard after \(pasteboard.lifetime, format: .units(allowed: [.minutes, .seconds], width: .wide))."
                )
            }

            Section {
                Button("Continue") { isConfirmingBackup = true }
                    .foregroundStyle(palette.primary)
                    .confirmation("Have you saved your recovery words?", action: "Yes", role: .confirm,
                                  isPresented: $isConfirmingBackup, perform: continueSetup) {
                        Text("Make sure you've written down all the words in order and stored them somewhere safe.")
                    }
            }
        }
        .navigationTitle("Recovery Phrase")
        .toolbarTitleDisplayMode(.inline)
        .onDisappear {
            if isSaved { phrase = nil }
        }
    }
}

#Preview("Public test phrase") {
    if let phrase = try? RecoveryPhrase(
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
    {
        NavigationStack {
            RecoveryPhraseScreen(initialPhrase: phrase, isSaved: false, pasteboard: PreviewRecoveryPasteboard(),
                                 continueSetup: {})
        }
        .tint(RenderedPalette(OriginalAppearance.palette).primary)
    }
}

/// A pasteboard for previews that copies nothing.
nonisolated private struct PreviewRecoveryPasteboard: RecoveryCopying {
    let lifetime: Duration = .seconds(60)

    func copy(_ phrase: RecoveryPhrase) {}
}
