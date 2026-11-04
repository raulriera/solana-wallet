import Portfolio
import RPC
import SwiftUI
import Transactions
import Wallet

/// Shows one token's balance and, when known, its value, price, and 24-hour change.
struct TokenDetailScreen: View {
    @Environment(\.palette) private var palette
    @Environment(PrivateBalanceStore.self) private var privateBalances
    let holding: Holding
    let account: Account
    let network: Network
    let privateBalance: PrivateBalanceModel

    var body: some View {
        let walletPrivateBalance = holding.id == .nativeSOL ? privateBalances.balance(for: account, on: network) : nil
        let privateStatus = walletPrivateBalance?.status
        let isPrivateBalanceStale = walletPrivateBalance?.isStale ?? false
        Form {
            Section {
                TokenTitleCard(symbol: holding.displaySymbol, name: holding.displayName, logoURL: holding.logoURL)
            }

            Section {
                if let amount = holding.amount {
                    LabeledContent("Balance") {
                        TokenBalance(amount: amount, symbol: holding.displaySymbol)
                            .textSelection(.enabled)
                    }
                }
                if let otherOwner = holding.otherOwner {
                    LabeledContent("Owner") {
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

            if holding.id == .nativeSOL {
                PrivateBalanceSections(isTurningOn: privateBalance.isTurningOn,
                                       turnOn: PrivateBalanceTurnOnAction(model: privateBalance),
                                       status: privateStatus,
                                       symbol: holding.displaySymbol,
                                       isStale: isPrivateBalanceStale)
                    .environment(\.moveBalance,
                                 PrivateBalanceMoveAction(model: privateBalance, privateBalances: privateBalances,
                                                          account: account, network: network,
                                                          publicLamports: holding.amount?.units ?? 0))
            }
        }
        .animation(.default, value: privateStatus)
        .animation(.default, value: isPrivateBalanceStale)
        .task(id: holding.id) {
            if holding.id == .nativeSOL { await privateBalances.refresh(account, on: network) }
        }
        .monospacedDigit()
        .navigationTitle(holding.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if holding.id != .nativeSOL {
                ToolbarItem(placement: .primaryAction) {
                    TokenActionsMenu(token: holding.id, symbol: holding.displaySymbol)
                }
            }
        }
    }
}

#Preview {
    let store = PrivateBalanceStore.preview
    if let address = try? Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK") {
        NavigationStack {
            TokenDetailScreen(holding: Holding(id: .nativeSOL, amount: Amount(units: 12_500_000_000, decimals: 9),
                                               name: "Solana", symbol: "SOL", imageURL: nil,
                                               valuation: Valuation(pricePerUnit: 166, total: 2_075, currency: "USD",
                                                                    dayChange: Decimal(string: "0.0129"))),
                              account: Account(id: UUID(), recoveryID: UUID(), address: address, path: .solana),
                              network: .devnet, privateBalance: PrivateBalanceModel())
        }
        .environment(store)
    }
}

#Preview("Other owner") {
    let store = PrivateBalanceStore.preview
    if let address = try? Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK") {
        NavigationStack {
            TokenDetailScreen(holding: Holding(id: .asset("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"), amount: nil,
                                               otherOwner: try? Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"),
                                               name: "Tether USD", symbol: "USDT", imageURL: nil, valuation: nil),
                              account: Account(id: UUID(), recoveryID: UUID(), address: address, path: .solana),
                              network: .devnet, privateBalance: PrivateBalanceModel())
        }
        .environment(store)
    }
}

private extension TransactionStore {
    static var preview: TransactionStore {
        TransactionStore(directory: .temporaryDirectory) { _ in throw TransactionCoordinatorError.unsupportedNetwork }
    }
}

private extension PrivateBalanceStore {
    static var preview: PrivateBalanceStore {
        PrivateBalanceStore(balances: PreviewPrivateBalances(), transactions: .preview,
                            providers: ProviderStore(service: "preview"))
    }
}

/// A private-balance service for previews whose private balance is off.
private struct PreviewPrivateBalances: PrivateBalancing {
    func enable(_ account: Account, on network: Network) async throws {}

    func refresh(_ account: Account, on network: Network) async throws -> PrivateBalanceStatus { .off(isRegistered: false) }

    func savedStatus(of account: Account, on network: Network) async throws -> PrivateBalanceStatus? { nil }

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
