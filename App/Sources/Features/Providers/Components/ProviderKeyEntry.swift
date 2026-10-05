import SwiftUI

/// Isolates key typing from the form's unrelated appearance and layout work.
struct ProviderKeyEntry: View {
    @Bindable var input: ProviderKeyInput
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        SecureField("Helius API key", text: $input.key)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit { isFocused = false }
    }
}
