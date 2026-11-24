import Privacy
import SwiftUI
import Transactions

/// Shows an asset's private balance: a Turn On button while it's off, or the available and pending amounts with their
/// actions.
struct PrivateBalanceSections: View {
    let isTurningOn: Bool
    let turnOn: PrivateBalanceTurnOnAction
    /// The account's private balance, or `nil` before the first read.
    let status: PrivateBalanceStatus?
    let asset: Asset
    /// The pool's asset of ``asset``.
    let privateAsset: PrivateAsset
    /// The account's public balance of the asset, whose decimals the private amounts share.
    let publicBalance: TokenAmount
    /// Whether the last read failed.
    let isStale: Bool
    /// The action that reads the balance again, or `nil` where nothing can.
    let refresh: RefreshAction?

    var body: some View {
        switch status {
        case .off(let isRegistered)?:
            Section {
                Button {
                    turnOn()
                } label: {
                    PendingLabel(title: "Turn On Private Balance", isPending: isTurningOn)
                }
                .disabled(isTurningOn)
            } header: {
                Text("Private Balance")
            } footer: {
                if isRegistered {
                    Text("This account already uses private balances. Turn them on to see its private balance.",
                         comment: "Footer under the button that turns private balances on, for an account that turned them on before, such as before its wallet was imported again.")
                } else {
                    Text("Private balances hide amounts from others on the network, but not addresses.",
                         comment: "Footer under the button that turns private balances on.")
                }
            }
        case .balance?, .unregistered?:
            let balance = status?.balance(of: privateAsset) ?? .zero
            PrivateBalanceAmountSection(
                available: TokenAmount(amount: balance.available, decimals: publicBalance.decimals),
                pending: TokenAmount(amount: balance.pending, decimals: publicBalance.decimals),
                asset: asset, isStale: isStale, refresh: refresh
            )
        case nil where isStale:
            PrivateBalanceAmountSection(available: nil, pending: nil,
                                        asset: asset, isStale: isStale, refresh: refresh)
        case .unavailable?, nil:
            EmptyView()
        }
    }
}
