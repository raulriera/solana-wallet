import Observation
import Portfolio
import RPC
import SwiftUI
import Transactions

/// Shows one token's balance and, when known, its value, price, and 24-hour change; removes any token except native SOL.
///
/// Devnet has no prices, so its tokens show only their balance and a note that they have no monetary value.
/// A token whose account another address controls shows that address instead of a balance, value, or price.
struct TokenDetailScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.network) private var network
    let holding: Holding
    /// The window's token removals; a confirmed removal closes the screen.
    let removal: TokenRemovalModel

    var body: some View {
        Form {
            Section {
                TokenTitleCard(symbol: holding.displaySymbol, name: holding.displayName, logoURL: holding.logoURL)
            }
            .listRowBackground(palette.surface)

            Section {
                if let amount = holding.amount {
                    LabeledContent("Balance") {
                        TokenBalance(amount: amount, symbol: holding.displaySymbol)
                            .textSelection(.enabled)
                    }
                }
                if let otherOwner = holding.otherOwner {
                    LabeledContent("Owner") {
                        // A narrow address keeps the row on one line and shows only the address's start and end;
                        // copying takes it whole.
                        Text(otherOwner.value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: 130, alignment: .trailing)
                    }
                }
                if let value = holding.knownValue {
                    LabeledContent("Value") {
                        TokenValue(total: value.total, currency: value.currency)
                    }
                }
                if let price = holding.knownPrice {
                    LabeledContent("Price") {
                        TokenPrice(price: price.price, currency: price.currency)
                    }
                }
                if let change = holding.valuation?.dayChange {
                    LabeledContent {
                        DayChangeLabel(change: change)
                    } label: {
                        // The value already says "over 24 hours", so VoiceOver doesn't repeat it.
                        Text("24h Change")
                            .accessibilityLabel(Text("Change"))
                    }
                }
            } header: {
                Text("Holdings")
            } footer: {
                Group {
                    if holding.otherOwner != nil {
                        Label {
                            Text("You don’t own this account. Funds sent here will be lost.",
                                 comment: "Warning under a token whose account at the person's address another address controls.")
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill")
                        }
                        .labelStyle(.warning)
                    } else if network == .devnet {
                        Text("Devnet tokens are for testing and have no monetary value.",
                             comment: "Footer under a token's balance in a window on Devnet, Solana's test network.")
                    } else if let currency = holding.knownValue?.currency {
                        Text("Values are quoted in \(currency).",
                             comment: "Footer under a token's value and price. The variable is the quote currency code, such as USD.")
                    }
                }
                .foregroundStyle(palette.secondaryText)
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
                    TokenActionsMenu(token: holding.id, symbol: holding.displaySymbol, removal: removal)
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
                          removal: TokenRemovalModel(coordinator: PreviewPortfolio()))
    }
}

#Preview("Other owner") {
    NavigationStack {
        TokenDetailScreen(holding: Holding(id: .asset("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"), amount: nil,
                                           otherOwner: try? Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"),
                                           name: "Tether USD", symbol: "USDT", imageURL: nil, valuation: nil),
                          removal: TokenRemovalModel(coordinator: PreviewPortfolio()))
    }
}

/// Keeps the preview local: it has no tokens and never observes, looks up, adds, or removes one.
@Observable
private final class PreviewPortfolio: PortfolioCoordinating {
    var update: Update? { nil }
    var holdings: [Holding] { [] }
    var error: PortfolioError? { nil }

    /// Accepts the preview's observation without reading a wallet.
    /// - Parameters:
    ///   - owner: The preview's wallet address.
    ///   - isActive: Whether the preview's scene is active.
    func observe(for owner: String?, isActive: Bool) async {}

    /// Accepts the preview's refresh without loading anything.
    func refresh() async {}

    /// Finds no token, because the preview reads no mints.
    /// - Parameter mint: The preview's pasted mint address.
    /// - Returns: Never; every lookup fails.
    /// - Throws: `TokenLookupError.notToken` for every address.
    func token(at mint: Address) async throws -> TokenPreview {
        throw TokenLookupError.notToken
    }

    /// Accepts the preview's addition without saving it.
    /// - Parameter token: The preview's token.
    func add(_ token: ListedToken) async throws {}

    /// Accepts the preview's removal without saving it.
    /// - Parameter mint: The preview's token mint.
    func remove(_ mint: Address) async throws {}
}
