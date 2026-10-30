import Accessibility
import SwiftUI
import Wallet

/// A button that copies recovery words and shows that they're copied until they expire.
struct CopyWordsButton: View {
    @Environment(\.canDisplayRecovery) private var canDisplayRecovery
    @State private var copiedUntil: ContinuousClock.Instant?
    /// The words to copy, or `nil` when they're no longer in memory.
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

    /// Copies the words and confirms the copy.
    private func copyWords() {
        guard let phrase, canDisplayRecovery else { return }
        pasteboard.copy(phrase)
        withAnimation { copiedUntil = ContinuousClock.now + pasteboard.lifetime }
        AccessibilityNotification.Announcement(String(localized: "Recovery words copied")).post()
    }

    /// Waits until the copied words expire, then resets the button.
    private func offerCopyAfterExpiry() async {
        guard let copiedUntil else { return }
        do {
            try await Task.sleep(until: copiedUntil)
            withAnimation { self.copiedUntil = nil }
        } catch {
        }
    }
}
