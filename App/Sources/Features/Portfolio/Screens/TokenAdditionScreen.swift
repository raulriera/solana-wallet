import Portfolio
import SwiftUI

/// Takes a pasted mint address and previews the token it names.
struct TokenAdditionScreen: View {
    let addition: TokenAdditionModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Group {
                        if addition.text.isEmpty {
                            Text("Mint address")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(addition.text)
                                .monospaced()
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PasteButton(payloadType: String.self) { paste($0.first ?? "") }
                        .themedButtonBorder()
                }

                if let rejection = addition.rejection {
                    Label(rejection.message, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.warning)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            }

            if let preview = addition.preview {
                let token = Holding(preview: preview)
                Section {
                    TokenTitleCard(symbol: token.asset.displaySymbol, name: token.asset.displayName,
                                   logoURL: token.logoURL)
                } footer: {
                    Text("Anyone can name a token anything. Add only addresses you trust.")
                }
            }
        }
        .animation(.default, value: addition.rejection)
        .animation(.default, value: addition.preview != nil)
        .confirmationAction("Add Token", isEnabled: addition.preview != nil, action: addition.add)
        .navigationTitle("Add Token")
        .toolbarTitleDisplayMode(.inline)
    }

    /// Takes pasted text with animation.
    ///
    /// - Parameter text: The pasteboard's text.
    private func paste(_ text: String) {
        withAnimation { addition.paste(text) }
    }
}
