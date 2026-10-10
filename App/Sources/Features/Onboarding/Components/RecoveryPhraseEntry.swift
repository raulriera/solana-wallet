import SwiftUI

/// Isolates recovery typing from the form's unrelated appearance and layout work, with a control to check the words.
struct RecoveryPhraseEntry: View {
    @Bindable var input: RecoveryInput
    @FocusState.Binding var focusedField: RecoveryInput.Field?

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
                .focused($focusedField, equals: input.phraseField)
                .transition(.opacity)
            }

            RevealButton(isRevealed: input.showsWords, showTitle: "Show words",
                         hideTitle: "Hide words", action: toggleWords)
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
