import Portfolio
import SwiftUI

/// The private balance of SOL's details: Turn On while private balances are off, then the available and pending SOL,
/// with the actions as rows under them.
///
/// Nothing shows before the first read, or where private balances aren't available, so the sections animate in.
struct PrivateBalanceSections: View {
    @Environment(\.palette) private var palette
    /// Whether an attempt to turn private balances on is waiting or running.
    let isTurningOn: Bool
    /// Turns private balances on.
    let turnOn: PrivateBalanceTurnOnAction
    /// The account's last read private balance, or `nil` before the first read.
    let status: PrivateBalanceStatus?
    /// Whether some private SOL is available to move to the public balance.
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
                    // A wallet imported again doesn't look like it lost its private SOL.
                    if isRegistered {
                        Text("This account already uses private balances. Turn them on to see its private balance. Private balances hide amounts from others on the network. Addresses stay visible, and the selected provider, which makes the proofs, can see amounts.",
                             comment: "Footer under the button that turns private balances on, for an account that turned them on before, such as before its wallet was imported again.")
                    } else {
                        Text("Private balances hide amounts from others on the network. Addresses stay visible, and the selected provider, which makes the proofs, can see amounts.",
                             comment: "Footer under the button that turns private balances on.")
                    }
                }
                .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
        case .unregistered?:
            Section("Private Balance") {
                LabeledContent("Available") {
                    TokenBalance(amount: Amount(lamports: 0), symbol: symbol)
                }
                PrivateBalanceActions(canMakePublic: canMakePublic)
            }
            .listRowBackground(palette.surface)
        case .balance(let available, let pending)?:
            Section {
                LabeledContent("Available") {
                    TokenBalance(amount: Amount(lamports: available), symbol: symbol)
                        .textSelection(.enabled)
                }
                if pending > 0 {
                    LabeledContent("Pending") {
                        TokenBalance(amount: Amount(lamports: pending), symbol: symbol)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                PrivateBalanceActions(canMakePublic: canMakePublic)
            } header: {
                Text("Private Balance")
            } footer: {
                if pending > 0 {
                    Text("Pending SOL becomes available when the network reports it, usually within a minute.",
                         comment: "Footer under a private balance with pending SOL, such as a recent deposit.")
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .listRowBackground(palette.surface)
        case .unavailable?, nil:
            EmptyView()
        }
    }
}
