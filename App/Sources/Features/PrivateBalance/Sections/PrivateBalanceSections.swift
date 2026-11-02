import Portfolio
import SwiftUI

/// Shows SOL's private balance: a Turn On button while it's off, or the available and pending SOL with its actions.
struct PrivateBalanceSections: View {
    @Environment(\.palette) private var palette
    let isTurningOn: Bool
    let turnOn: PrivateBalanceTurnOnAction
    /// The account's private balance, or `nil` before the first read.
    let status: PrivateBalanceStatus?
    /// Whether the last read failed.
    let isOutdated: Bool
    let canMakePublic: Bool
    let symbol: String

    var body: some View {
        switch status {
        case .off(let isRegistered)?:
            Section {
                Button {
                    turnOn()
                } label: {
                    HStack {
                        Text("Turn On Private Balance")
                        Spacer()
                        if isTurningOn {
                            ProgressView()
                        }
                    }
                }
                .foregroundStyle(palette.accent)
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
            .listRowBackground(palette.surface)
        case .unregistered?, .balance?, nil where isOutdated:
            Section {
                if let lamports {
                    LabeledContent("Available") {
                        TokenBalance(amount: Amount(lamports: lamports.available), symbol: symbol)
                            .textSelection(.enabled)
                    }
                    if lamports.pending > 0 {
                        LabeledContent("Pending") {
                            TokenBalance(amount: Amount(lamports: lamports.pending), symbol: symbol)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    PrivateBalanceActions(canMakePublic: canMakePublic)
                        .disabled(isOutdated)
                }
            } header: {
                Text("Private Balance")
            } footer: {
                Group {
                    if isOutdated {
                        Text("Couldn't update private balance.",
                             comment: "Footer under a private balance that the last read couldn't update, such as when a network request fails. The balance shown is the last one read or saved, if any.")
                    } else if let lamports, lamports.pending > 0 {
                        Text("Pending SOL becomes available when the network reports it, usually within a minute.",
                             comment: "Footer under a private balance with pending SOL, such as a recent deposit.")
                    }
                }
                .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
        case .unavailable?, nil:
            EmptyView()
        }
    }

    /// The available and pending SOL, or `nil` without a balance.
    private var lamports: (available: UInt64, pending: UInt64)? {
        switch status {
        case .balance(let available, let pending)?: (available, pending)
        case .unregistered?: (0, 0)
        case .off?, .unavailable?, nil: nil
        }
    }
}
