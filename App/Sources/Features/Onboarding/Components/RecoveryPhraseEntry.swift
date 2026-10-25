import Accessibility
import SwiftUI

/// The recovery words field, with a show/hide button and feedback for each rejection.
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
