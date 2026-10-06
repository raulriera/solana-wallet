import Portfolio
import RPC
import SwiftUI

/// Shows one token's balance, value, and network.
struct TokenDetailScreen: View {
    @Environment(\.palette) private var palette
    @State private var contentInset = LayoutMetrics.contentMargin
    let holding: Holding
    let network: Network

    var body: some View {
        Form {
            Section {
                TitleCardContent(title: "\(holding.displayName)", message: "\(holding.displaySymbol) · Solana",
                                 systemImage: "creditcard.fill")
            }
            .listRowBackground(palette.surface)

            Section {
                LabeledContent("Balance") {
                    TokenBalance(amount: holding.amount, symbol: holding.displaySymbol)
                        .textSelection(.enabled)
                }
                LabeledContent("Value") {
                    if let value = holding.knownValue {
                        Text(value.total, format: .currency(code: value.currency))
                    } else {
                        Text("Unavailable")
                    }
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
                                           valuation: Valuation(pricePerUnit: 166, total: 2_075, currency: "USD")),
                          network: .mainnet)
    }
}
