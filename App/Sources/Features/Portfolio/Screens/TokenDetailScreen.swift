import Portfolio
import RPC
import SwiftUI
import Transactions

/// Shows one token's balance and, when known, its value, price, and 24-hour change; removes any token except native SOL.
///
/// Native SOL also shows the account's private balance, read again each time the screen appears.
/// Devnet has no prices, so its tokens show only their balance and a note that they have no monetary value.
/// A token whose account another address controls shows that address instead of a balance, value, or price.
struct TokenDetailScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.network) private var network
    let holding: Holding
    /// The window's private balance, which native SOL's details show and turn on with ``privateBalanceLifecycle()``.
    let privateBalance: PrivateBalanceModel

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
                        // Middle truncation hides characters only on screen, so copying takes the whole address.
                        // Don't use the short address format here: it changes the text itself, so a copy would take
                        // only its first and last four characters.
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

            if holding.id == .nativeSOL {
                PrivateBalanceSections(model: privateBalance, symbol: holding.displaySymbol)
                    // The rows open moves with the account's public SOL without holding the private balance.
                    .environment(\.moveBalance,
                                 PrivateBalanceMoveAction(model: privateBalance,
                                                          publicLamports: holding.amount?.units ?? 0))
            }
        }
        .animation(.default, value: privateBalance.status)
        .task(id: holding.id) {
            if holding.id == .nativeSOL { await privateBalance.refresh() }
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
                    TokenActionsMenu(token: holding.id, symbol: holding.displaySymbol)
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
                          privateBalance: PrivateBalanceModel(balances: PreviewPrivateBalances(),
                                                              transactions: .preview, network: .devnet))
    }
}

#Preview("Other owner") {
    NavigationStack {
        TokenDetailScreen(holding: Holding(id: .asset("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"), amount: nil,
                                           otherOwner: try? Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"),
                                           name: "Tether USD", symbol: "USDT", imageURL: nil, valuation: nil),
                          privateBalance: PrivateBalanceModel(balances: PreviewPrivateBalances(),
                                                              transactions: .preview, network: .devnet))
    }
}

private extension TransactionStore {
    /// Keeps the preview local: no network has a coordinator, so a deposit never opens, and no records are read.
    static var preview: TransactionStore {
        TransactionStore(directory: .temporaryDirectory) { _ in throw SubmitterError.noProviders }
    }
}

/// Keeps the preview local: it has no tokens and never observes, looks up, adds, or removes one.
private struct PreviewPrivateBalances: PrivateBalancing {
    func enable(_ account: Account, on network: Network) async throws {}

    func refresh(_ account: Account, on network: Network) async throws -> PrivateBalanceStatus { .off(isRegistered: false) }

    func prepare(_ request: PrivateTransactionRequest, from account: Account, on network: Network) async throws
        -> PreparedPrivateTransaction {
        throw PrivateBalanceError.unavailable
    }

    func complete(_ transaction: PreparedPrivateTransaction, with confirmation: Confirmation) async throws
        -> PrivateBalanceStatus {
        .off(isRegistered: false)
    }

    func outstandingCodes(of account: Account, on network: Network) async throws -> [OutstandingRedeemCode] { [] }

    func removeAll() async throws {}
}
