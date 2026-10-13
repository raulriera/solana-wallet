import Portfolio
import RPC
import SwiftUI

/// Shows one token's balance, value, price, and 24-hour change, and removes any token except native SOL.
struct TokenDetailScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let holding: Holding
    /// Removes a confirmed token from the wallet's list; the screen then closes itself.
    let remove: (Holding) -> Void

    var body: some View {
        Form {
            Section {
                TokenTitleCard(symbol: holding.displaySymbol, name: holding.displayName, logoURL: holding.logoURL)
            }
            .listRowBackground(palette.surface)

            Section {
                LabeledContent("Balance") {
                    TokenBalance(amount: holding.amount, symbol: holding.displaySymbol)
                        .textSelection(.enabled)
                }
                LabeledContent("Value") {
                    if let value = holding.knownValue {
                        TokenValue(total: value.total, currency: value.currency)
                    } else {
                        Text("Unavailable")
                    }
                }
                LabeledContent("Price") {
                    if let price = holding.knownPrice {
                        TokenPrice(price: price.price, currency: price.currency)
                    } else {
                        Text("Unavailable")
                    }
                }
                LabeledContent {
                    if let change = holding.valuation?.dayChange {
                        DayChangeLabel(change: change)
                    } else {
                        Text("Unavailable")
                    }
                } label: {
                    // The value already says "over 24 hours", so VoiceOver doesn't repeat it.
                    Text("24h Change")
                        .accessibilityLabel(Text("Change"))
                }
            } header: {
                Text("Holdings")
            } footer: {
                if let currency = holding.knownValue?.currency {
                    Text("Values are quoted in \(currency).")
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .listRowBackground(palette.surface)
        }
        .monospacedDigit()
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .navigationTitle(holding.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Native SOL isn't part of the token list, so it always stays.
            if holding.id != .nativeSOL {
                ToolbarItem(placement: .primaryAction) {
                    TokenActionsMenu(token: holding) { token in
                        remove(token)
                        // Compact width goes back to the list; expanded width clears the selection.
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TokenDetailScreen(holding: Holding(id: .nativeSOL, amount: Amount(units: 12_500_000_000, decimals: 9),
                                           name: "Solana", symbol: "SOL", imageURL: nil,
                                           valuation: Valuation(pricePerUnit: 166, total: 2_075, currency: "USD",
                                                                dayChange: Decimal(string: "0.0129"))),
                          remove: { _ in })
    }
}
