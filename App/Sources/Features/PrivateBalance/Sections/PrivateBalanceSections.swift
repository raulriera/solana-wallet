import Portfolio
import SwiftUI

/// Shows an asset's private balance: a Turn On button while it's off, or the available and pending amounts with their
/// actions.
struct PrivateBalanceSections: View {
    @Environment(\.palette) private var palette
    let isTurningOn: Bool
    let turnOn: PrivateBalanceTurnOnAction
    /// The account's private balance, or `nil` before the first read.
    let status: PrivateBalanceStatus?
    let asset: PrivateAsset
    let symbol: String
    /// Whether the last read failed.
    let isStale: Bool

    var body: some View {
        switch status {
        case .off(let isRegistered)?:
            Section {
                Button {
                    turnOn()
                } label: {
                    PendingLabel(title: "Turn On Private Balance", isPending: isTurningOn)
                }
                .foregroundStyle(palette.primary)
                .disabled(isTurningOn)
            } header: {
                Text("Private Balance")
            } footer: {
                Group {
                    if isRegistered {
                        Text("This account already uses private balances. Turn them on to see its private balance. Private balances hide amounts from others on the network. Addresses stay visible, and the service that finds your private payments can tell which ones are yours and when you spend them.",
                             comment: "Footer under the button that turns private balances on, for an account that turned them on before, such as before its wallet was imported again.")
                    } else {
                        Text("Private balances hide amounts from others on the network. Addresses stay visible, and the service that finds your private payments can tell which ones are yours and when you spend them.",
                             comment: "Footer under the button that turns private balances on.")
                    }
                }
                .foregroundStyle(palette.secondaryText)
            }
        case .balance?, .unregistered?:
            let balance = status?.balance(of: asset) ?? .zero
            PrivateBalanceAmountSection(available: Amount(units: balance.available, decimals: asset.decimals),
                                        pending: Amount(units: balance.pending, decimals: asset.decimals),
                                        symbol: symbol, isStale: isStale)
        case nil where isStale:
            PrivateBalanceAmountSection(available: nil, pending: nil,
                                        symbol: symbol, isStale: isStale)
        case .unavailable?, nil:
            EmptyView()
        }
    }
}
