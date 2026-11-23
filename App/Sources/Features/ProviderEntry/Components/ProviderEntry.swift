import SwiftUI

/// A field for typing or pasting a provider entry, such as an API key or a URL.
struct ProviderEntry: View {
    /// The kind of text that an entry holds.
    nonisolated enum Kind {
        case key
        case url
    }

    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let label: LocalizedStringResource
    let kind: Kind

    var body: some View {
        HStack(spacing: 16) {
            Group {
                switch kind {
                case .key:
                    SecureField(label, text: $text)
                case .url:
                    TextField(label, text: $text)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .writingToolsBehavior(.disabled)
                }
            }
            .accessibilityLabel(Text(label))
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit { isFocused = false }

            PasteButton(payloadType: String.self) { text = $0.first ?? "" }
                .themedButtonBorder()
        }
    }
}
