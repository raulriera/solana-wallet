import SwiftUI

/// A field for typing or pasting a provider entry, such as an API key or an RPC URL.
struct ProviderEntry<Field: View>: View {
    @Environment(\.palette) private var palette
    @Bindable var input: ProviderEntryModel
    @FocusState.Binding var isFocused: Bool
    @ViewBuilder let field: (Binding<String>) -> Field

    var body: some View {
        HStack(spacing: 16) {
            field($input.text)
                .foregroundStyle(palette.text)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { isFocused = false }

            PasteTextButton { input.text = $0 }
        }
    }
}
