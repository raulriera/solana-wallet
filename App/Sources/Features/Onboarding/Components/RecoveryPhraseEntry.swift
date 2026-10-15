import Accessibility
import SwiftUI

/// Isolates recovery typing from the form's unrelated appearance and layout work, with a control to check the words
/// and feedback for each rejected check.
struct RecoveryPhraseEntry: View {
    @Environment(\.palette) private var palette
    @Bindable var input: RecoveryEntryModel
    @FocusState.Binding var focusedField: RecoveryEntryModel.Field?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Overlapping the fields keeps the text in place while one fades into the other.
            ZStack(alignment: .leading) {
                Group {
                    if input.showsWords {
                        TextField("Recovery words", text: $input.phrase, axis: .vertical)
                            .lineLimit(3...6)
                    } else {
                        SecureField("Recovery words", text: $input.phrase)
                            .submitLabel(.next)
                            .onSubmit { focusedField = input.passphraseField }
                    }
                }
                .accessibilityLabel("Recovery words")
                // Only the text takes the window's text color; the reveal button keeps the tint and its disabled look.
                .foregroundStyle(palette.primaryText)
                .focused($focusedField, equals: input.phraseField)
                .transition(.opacity)
            }

            RevealButton(isRevealed: input.showsWords, showTitle: "Show words",
                         hideTitle: "Hide words", action: toggleWords)
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

    /// Switches native controls, keeping focus only when revealing.
    ///
    /// A hidden field that regains focus replaces its text on the next keystroke, so hiding ends editing and
    /// checks the words, as leaving the field does.
    private func toggleWords() {
        let wasEditing = focusedField == input.phraseField
        withAnimation {
            input.showsWords.toggle()
            if wasEditing { focusedField = input.showsWords ? .revealedPhrase : nil }
        }
        if wasEditing, !input.showsWords, input.hasPhrase { input.validate() }
    }
}
