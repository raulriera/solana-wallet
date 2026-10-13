import SwiftUI

/// Isolates typing and pasting a provider entry, such as an API key or an RPC URL, from the form's unrelated
/// appearance and layout work.
struct ProviderEntry<Field: View>: View {
    @Environment(\.palette) private var palette
    @Bindable var input: ProviderEntryModel
    @FocusState.Binding var isFocused: Bool
    /// The text field, built around the entry's text.
    @ViewBuilder let field: (Binding<String>) -> Field

    var body: some View {
        HStack(spacing: 16) {
            field($input.text)
                // Only the text takes the window's text color; the Paste button keeps the tint and its disabled look.
                .foregroundStyle(palette.primaryText)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { isFocused = false }

            PasteTextButton { input.text = $0 }
        }
    }
}
