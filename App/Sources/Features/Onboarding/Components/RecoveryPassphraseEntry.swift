import SwiftUI

/// Isolates original-passphrase typing without applying text normalization, with a control to check it exactly.
struct RecoveryPassphraseEntry: View {
    @Environment(\.palette) private var palette
    @Bindable var input: RecoveryInput
    @FocusState.Binding var focusedField: RecoveryInput.Field?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Overlapping the fields keeps the text in place while one fades into the other.
            ZStack(alignment: .leading) {
                Group {
                    if input.showsPassphrase {
                        // Smart quotes and dashes follow the keyboard type; this one keeps them as typed, like the hidden field.
                        TextField("Optional", text: $input.passphrase)
                            .keyboardType(.asciiCapable)
                    } else {
                        SecureField("Optional", text: $input.passphrase)
                    }
                }
                .accessibilityLabel("BIP-39 passphrase, optional")
                // Only the text takes the window's text color; the reveal button keeps the tint and its disabled look.
                .foregroundStyle(palette.primaryText)
                .focused($focusedField, equals: input.passphraseField)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .transition(.opacity)
            }

            RevealButton(isRevealed: input.showsPassphrase, showTitle: "Show passphrase",
                         hideTitle: "Hide passphrase", action: togglePassphrase)
        }
    }

    /// Switches native controls, keeping focus only when revealing.
    ///
    /// A hidden field that regains focus replaces its text on the next keystroke, so hiding ends editing.
    private func togglePassphrase() {
        let wasEditing = focusedField == input.passphraseField
        withAnimation {
            input.showsPassphrase.toggle()
            if wasEditing { focusedField = input.showsPassphrase ? .revealedPassphrase : nil }
        }
    }
}
