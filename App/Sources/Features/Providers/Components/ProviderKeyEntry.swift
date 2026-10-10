import SwiftUI

/// Isolates key typing and pasting from the form's unrelated appearance and layout work.
struct ProviderKeyEntry: View {
    @Bindable var input: ProviderKeyInput
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            SecureField("RPC API key", text: $input.key)
                .accessibilityLabel("RPC API key")
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { isFocused = false }

            PasteTextButton { input.key = $0 }
        }
    }
}
