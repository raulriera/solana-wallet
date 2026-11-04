import Portfolio
import SwiftUI

/// Takes a pasted mint address and previews the token it names.
struct TokenAdditionScreen: View {
    @Environment(\.palette) private var palette
    let addition: TokenAdditionModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Group {
                        if addition.text.isEmpty {
                            Text("Mint address")
                                .foregroundStyle(palette.secondaryText)
                        } else {
                            Text(addition.text)
                                .monospaced()
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(palette.text)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PasteTextButton(paste: paste)
                }

                if let rejection = addition.rejection {
                    Label(rejection.message, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.warning)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            } footer: {
                Text("Copy a token's mint address, then paste it here.")
                    .foregroundStyle(palette.secondaryText)
            }

            if let preview = addition.preview {
                let token = Holding(preview: preview)
                Section {
                    TokenTitleCard(symbol: token.displaySymbol, name: token.displayName, logoURL: token.logoURL)
                } footer: {
                    Text("Anyone can name a token anything. Add only addresses you trust.")
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .animation(.default, value: addition.rejection)
        .animation(.default, value: addition.preview != nil)
        .confirmationAction("Add Token", isEnabled: addition.preview != nil, action: addition.add)
        .navigationTitle("Add Token")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Takes pasted text with animation.
    ///
    /// - Parameter text: The pasteboard's text.
    private func paste(_ text: String) {
        withAnimation { addition.paste(text) }
    }
}
