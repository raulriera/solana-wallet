import Accessibility
import SwiftUI
import Wallet

/// Presents a prepared recovery phrase for backup without generating or storing it.
struct RecoveryPhraseScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.canDisplayRecovery) private var canDisplayRecovery
    @State private var contentInset = LayoutMetrics.contentMargin
    @State private var isConfirmingBackup = false
    @State private var phrase: RecoveryPhrase?
    @State private var copyCount = 0
    let isSaved: Bool
    let pasteboard: any RecoveryCopying
    let continueSetup: () -> Void

    /// Shows the words it opened with until the wallet is saved and the next step covers this screen.
    /// - Parameters:
    ///   - initialPhrase: The prepared words when the screen opens; later values are ignored.
    ///   - isSaved: Whether the wallet is saved; its words then leave memory once this screen is covered.
    ///   - pasteboard: Copies the words to this device only, for a limited time.
    ///   - continueSetup: Saves the wallet after the user confirms their backup.
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
            .listRowBackground(palette.surface)

            Section {
                if let phrase {
                    RecoveryWords(phrase: phrase)
                }

                Button("Copy Words", systemImage: "document.on.document", action: copyWords)
                    .disabled(phrase == nil || !canDisplayRecovery)
            } header: {
                Text("Recovery Words")
                    .foregroundStyle(palette.secondaryText)
            } footer: {
                Text(
                    "These words are your only way to restore this wallet. Neither the app nor iCloud can recover them. You'll need them if you lose this device or change its enrolled biometrics. Copied words stay on this device and clear from the clipboard after \(pasteboard.lifetime, format: .units(allowed: [.minutes, .seconds], width: .wide))."
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
        .sensoryFeedback(.success, trigger: copyCount)
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

    /// Copies the words while they're on screen, then confirms without changing the screen.
    private func copyWords() {
        guard let phrase, canDisplayRecovery else { return }
        pasteboard.copy(phrase)
        copyCount += 1
        AccessibilityNotification.Announcement(String(localized: "Recovery words copied")).post()
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
        .tint(RenderedPalette(OriginalAppearance.palette).accent)
    }
}

/// Keeps previews from copying the public test phrase to the real pasteboard.
nonisolated private struct PreviewRecoveryPasteboard: RecoveryCopying {
    let lifetime: Duration = .seconds(60)

    /// Accepts preview taps without copying anything.
    /// - Parameter phrase: The preview's public test phrase.
    func copy(_ phrase: RecoveryPhrase) {}
}
