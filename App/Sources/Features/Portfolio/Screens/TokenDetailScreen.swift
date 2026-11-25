import Portfolio
import Privacy
import RPC
import SwiftUI
import Transactions

/// Shows one token's balance and, when known, its value, price, and 24-hour change.
struct TokenDetailScreen: View {
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
                }
            }

            if let privateAsset, let publicBalance {
                PrivateBalanceSections(
                    isTurningOn: privateBalance.isTurningOn,
                    turnOn: PrivateBalanceTurnOnAction(model: privateBalance),
                    status: privateStatus,
                    asset: holding.asset,
                    privateAsset: privateAsset,
                    publicBalance: publicBalance,
                    isStale: isPrivateBalanceStale,
                    refresh: refresh
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
