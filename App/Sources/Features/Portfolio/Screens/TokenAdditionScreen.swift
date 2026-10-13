import Portfolio
import SwiftUI

/// Pastes a mint address and previews the token it names; the owning sheet adds the token.
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
                                .foregroundStyle(palette.primaryText)
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
            .listRowBackground(palette.surface)

            if let preview = addition.preview {
                let token = Holding(preview: preview)
                Section {
                    TokenTitleCard(symbol: token.displaySymbol, name: token.displayName, logoURL: token.logoURL)
                } footer: {
                    Text("Anyone can name a token anything. Add only addresses you trust.")
                        .foregroundStyle(palette.secondaryText)
                }
                .listRowBackground(palette.surface)
            }
        }
        .animation(.default, value: addition.rejection)
        // A preview only ever appears or clears, so its presence keys its motion.
        .animation(.default, value: addition.preview != nil)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .confirmationAction("Add Token", isEnabled: addition.preview != nil, action: addition.add)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle("Add Token")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Takes the pasted text, animating the change to the field and any rejection it brings.
    /// - Parameter text: The pasteboard's text.
    private func paste(_ text: String) {
        withAnimation { addition.paste(text) }
    }
}
