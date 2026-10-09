import SwiftUI

/// Isolates recovery typing from the form's unrelated appearance and layout work.
struct RecoveryPhraseEntry: View {
    @Bindable var input: RecoveryInput
    @FocusState.Binding var focusedField: RecoveryInput.Field?

    var body: some View {
        if input.showsWords {
            TextField("Recovery words", text: $input.phrase, axis: .vertical)
                .accessibilityLabel("Recovery words")
                .lineLimit(3...6)
                .focused($focusedField, equals: .revealedPhrase)
                .transition(.opacity)
        } else {
            SecureField("Recovery words", text: $input.phrase)
                .accessibilityLabel("Recovery words")
                .focused($focusedField, equals: .hiddenPhrase)
                .submitLabel(.next)
                .onSubmit { focusedField = .passphrase }
                .transition(.opacity)
        }
    }
}
