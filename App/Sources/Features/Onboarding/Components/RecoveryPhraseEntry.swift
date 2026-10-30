import Accessibility
import SwiftUI

/// A field for the recovery words, with a button that shows or hides them and feedback when they're rejected.
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
            var announcement = AttributedString(String(localized: message))
            announcement.accessibilitySpeechAnnouncementPriority = .low
            AccessibilityNotification.Announcement(announcement).post()
        }
    }
}
