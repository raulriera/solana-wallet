import SwiftUI

/// The BIP-39 passphrase field, with a button that shows or hides it.
struct RecoveryPassphraseEntry: View {
    @Bindable var input: RecoveryEntryModel
    @FocusState.Binding var focusedField: RecoveryEntryModel.Field?

    var body: some View {
        RevealableField(isRevealed: $input.showsPassphrase, focusedField: $focusedField, field: input.passphraseField,
                        revealedField: .revealedPassphrase, label: "BIP-39 passphrase, optional",
                        showTitle: "Show passphrase", hideTitle: "Hide passphrase") {
            // Smart quotes and dashes follow the keyboard type; this one keeps them as typed, like the hidden field.
            TextField("Optional", text: $input.passphrase)
                .keyboardType(.asciiCapable)
        } hidden: {
            SecureField("Optional", text: $input.passphrase)
        }
        .submitLabel(.done)
        .onSubmit { focusedField = nil }
    }
}
