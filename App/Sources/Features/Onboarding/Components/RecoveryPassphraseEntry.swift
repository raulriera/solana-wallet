import SwiftUI

/// Isolates original-passphrase typing without applying text normalization.
struct RecoveryPassphraseEntry: View {
    @Bindable var input: RecoveryInput
    @FocusState.Binding var focusedField: RecoveryInput.Field?

    var body: some View {
        SecureField("Optional", text: $input.passphrase)
            .accessibilityLabel("BIP-39 passphrase, optional")
            .focused($focusedField, equals: .passphrase)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
    }
}
