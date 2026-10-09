import Portfolio
import SwiftUI

/// Pastes a mint address and previews the token it names; the owning sheet adds the token.
struct TokenAdditionScreen: View {
    @Environment(\.palette) private var palette
    @State private var contentInset = LayoutMetrics.contentMargin
    let addition: TokenAddition

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

                    // The system button pastes without asking for permission, and turns off when there's nothing to paste.
                    // Only its shape and tint can change.
                    PasteButton(payloadType: String.self) { addition.paste($0.first ?? "") }
                        .buttonBorderShape(.capsule)
                        .tint(palette.accent)
                }

                if let message = addition.message {
                    Text(message)
                        .foregroundStyle(.red)
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
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .readableContentMargins(inset: $contentInset)
        .safeAreaBar(edge: .bottom) {
            Button("Add Token", action: addition.add)
                .buttonStyle(.primary)
                .disabled(addition.preview == nil)
                .padding(.horizontal, contentInset)
                .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle("Add Token")
        .navigationBarTitleDisplayMode(.inline)
    }
}
