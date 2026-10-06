import Accessibility
import SwiftUI
import Wallet

/// Copies recovery words and confirms on the button until the clipboard clears them.
struct CopyWordsButton: View {
    @Environment(\.canDisplayRecovery) private var canDisplayRecovery
    @State private var copiedUntil: ContinuousClock.Instant?
    /// The words on screen, or `nil` once they leave memory, which disables copying.
    let phrase: RecoveryPhrase?
    let pasteboard: any RecoveryCopying

    var body: some View {
        Button(action: copyWords) {
            Label {
                Text(copiedUntil == nil ? "Copy Words" : "Copied")
                    .contentTransition(.opacity)
            } icon: {
                Image(systemName: copiedUntil == nil ? "document.on.document" : "checkmark")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .disabled(phrase == nil || !canDisplayRecovery)
        .sensoryFeedback(.success, trigger: copiedUntil) { _, copiedUntil in copiedUntil != nil }
        .task(id: copiedUntil) { await offerCopyAfterExpiry() }
    }

    /// Copies the words while they're on screen, then confirms on the button until the clipboard clears them.
    private func copyWords() {
        guard let phrase, canDisplayRecovery else { return }
        pasteboard.copy(phrase)
        withAnimation { copiedUntil = ContinuousClock.now + pasteboard.lifetime }
        AccessibilityNotification.Announcement(String(localized: "Recovery words copied")).post()
    }

    /// Returns the button to its copy action once the copied words leave the clipboard.
    private func offerCopyAfterExpiry() async {
        guard let copiedUntil else { return }
        do {
            try await Task.sleep(until: copiedUntil)
            withAnimation { self.copiedUntil = nil }
        } catch {
            // A newer copy or the button's removal cancelled this wait; the newer state owns the label.
        }
    }
}
