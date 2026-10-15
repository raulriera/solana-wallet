import Accessibility
import SwiftUI

/// Isolates recovery typing from the form's unrelated appearance and layout work, with a control to check the words
/// and feedback for each rejected check.
struct RecoveryPhraseEntry: View {
    @Bindable var input: RecoveryEntryModel
    @FocusState.Binding var focusedField: RecoveryEntryModel.Field?

    var body: some View {
        RevealableField(isRevealed: $input.showsWords, focusedField: $focusedField, field: input.phraseField,
                        revealedField: .revealedPhrase, label: "Recovery words", showTitle: "Show words",
                        hideTitle: "Hide words") {
            TextField("Recovery words", text: $input.phrase, axis: .vertical)
                .lineLimit(3...6)
        } hidden: {
            SecureField("Recovery words", text: $input.phrase)
                .submitLabel(.next)
                .onSubmit { focusedField = input.passphraseField }
        }
        .sensoryFeedback(.error, trigger: input.rejectionCount)
        .onChange(of: input.rejectionCount) {
            guard let message = input.rejection?.message(in: input.phrase) else { return }
            // Checks run as focus leaves the words, so the reason waits until VoiceOver finishes reading.
            var announcement = AttributedString(String(localized: message))
            announcement.accessibilitySpeechAnnouncementPriority = .low
            AccessibilityNotification.Announcement(announcement).post()
        }
    }
}
