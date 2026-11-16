import Portfolio
import Privacy
import RPC
import SwiftUI
import Transactions
import Wallet

/// Shows one token's balance and, when known, its value, price, and 24-hour change.
struct TokenDetailScreen: View {
    @Environment(\.palette) private var palette
    @Environment(PrivateBalanceStore.self) private var privateBalances
    @Environment(\.refresh) private var refresh
    let holding: Holding
    let account: Account
    let network: Network
    let privateBalance: PrivateBalanceModel

    var body: some View {
        let publicBalance = holding.otherOwner == nil ? holding.balance : nil
        let privateAsset = publicBalance == nil ? nil : PrivateAsset(holding.id)
        let walletPrivateBalance = privateAsset != nil ? privateBalances.balance(for: account, on: network) : nil
        let privateStatus = walletPrivateBalance?.status
        let isPrivateBalanceStale = walletPrivateBalance?.isStale ?? false
        Form {
            Section {
                TokenTitleCard(symbol: holding.asset.displaySymbol, name: holding.asset.displayName,
                               logoURL: holding.logoURL)
            }

            Section {
                if let balance = holding.balance {
                    LabeledContent("Balance") {
                        TokenBalance(balance: balance, asset: holding.asset)
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

            if privateAsset != nil, let publicBalance {
                PrivateBalanceSections(
                    isTurningOn: privateBalance.isTurningOn,
                    turnOn: PrivateBalanceTurnOnAction(model: privateBalance),
                    status: privateStatus,
                    asset: holding.asset,
                    decimals: publicBalance.decimals,
                    isStale: isPrivateBalanceStale,
                    refresh: refresh
                )
                .environment(
                    \.moveBalance,
                    PrivateBalanceMoveAction(
                        model: privateBalance,
                        privateBalances: privateBalances,
                        account: account,
                        network: network,
                        holding: holding
                    )
                )
            }
        }
        .animation(.default, value: privateStatus)
        .animation(.default, value: isPrivateBalanceStale)
        .task(id: holding.id) {
            if privateAsset != nil { await privateBalances.refresh(account, on: network) }
        }
        .monospacedDigit()
        .navigationTitle(holding.asset.displayName)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if case .token(let mint) = holding.id {
                ToolbarItem(placement: .primaryAction) {
                    TokenActionsMenu(mint: mint, symbol: holding.asset.displaySymbol)
                }
            }
        }
    }
}

#Preview {
    let store = PrivateBalanceStore.preview
    if let address = try? Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK") {
        NavigationStack {
            TokenDetailScreen(holding: Holding(asset: .nativeSOL,
                                               balance: TokenAmount(amount: 12_500_000_000, decimals: 9),
                                               imageURL: nil,
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
    if let address = try? Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
       let usdt = try? Address("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB") {
        let mint = Mint(address: usdt, program: .token, decimals: 6,
                        metadata: TokenMetadata(name: "Tether USD", symbol: "USDT"))
        NavigationStack {
            TokenDetailScreen(holding: Holding(asset: .token(mint), balance: nil,
                                               otherOwner: try? Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"),
                                               imageURL: nil, valuation: nil),
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
                            rpcStore: RPCStore(service: "preview"))
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
