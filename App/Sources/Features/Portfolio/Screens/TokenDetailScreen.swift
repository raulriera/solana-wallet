import Portfolio
import RPC
import SwiftUI

/// Shows one token's balance, value, price, 24-hour change, and network.
struct TokenDetailScreen: View {
    @Environment(\.palette) private var palette
    @State private var contentInset = LayoutMetrics.contentMargin
    let holding: Holding
    let network: Network

    var body: some View {
        Form {
            Section {
                TitleCardContent(title: "\(holding.displayName)", message: "\(holding.displaySymbol) · Solana") {
                    TokenIcon(symbol: holding.displaySymbol, imageURL: holding.logoURL)
                }
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
            }
            .listRowBackground(palette.surface)

            Section {
                LabeledContent("Network") { Text(networkName) }
                LabeledContent("Asset") { Text(assetKind) }
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
        .readableContentMargins(inset: $contentInset)
        .background(palette.background)
        .navigationTitle(holding.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The network's name as people know it.
    private var networkName: LocalizedStringResource {
        switch network {
        case .mainnet: "Mainnet"
        case .devnet: "Devnet"
        }
    }

    /// Whether this is the network's own currency or a token.
    private var assetKind: LocalizedStringResource {
        holding.id == .nativeSOL ? "Native SOL" : "Fungible token"
    }
}

#Preview {
    NavigationStack {
        TokenDetailScreen(holding: Holding(id: .nativeSOL, amount: Amount(units: 12_500_000_000, decimals: 9),
                                           name: "Solana", symbol: "SOL", imageURL: nil,
                                           valuation: Valuation(pricePerUnit: 166, total: 2_075, currency: "USD",
                                                                dayChange: Decimal(string: "0.0129"))),
                          network: .mainnet)
    }
}
