import Portfolio
import SwiftUI

/// The private balance of SOL's details: Turn On while private balances are off, then the available and pending SOL,
/// with the actions as rows under them.
///
/// Nothing shows before the first read, or where private balances aren't available, so the sections animate in.
struct PrivateBalanceSections: View {
    @Environment(\.palette) private var palette
    let model: PrivateBalanceModel
    let symbol: String

    var body: some View {
        switch model.status {
        case .off(let isRegistered)?:
            Section {
                Button(action: model.turnOn) {
                    HStack {
                        Text("Turn On Private Balance")
                        Spacer()
                        if model.isTurningOn {
                            ProgressView()
                        }
                    }
                }
                .foregroundStyle(palette.accent)
                .disabled(model.isTurningOn)
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
                    TokenBalance(amount: Self.amount(0), symbol: symbol)
                }
                PrivateBalanceActions(canMakePublic: model.availableLamports != nil)
            }
            .listRowBackground(palette.surface)
        case .balance(let available, let pending)?:
            Section {
                LabeledContent("Available") {
                    TokenBalance(amount: Self.amount(available), symbol: symbol)
                        .textSelection(.enabled)
                }
                if pending > 0 {
                    LabeledContent("Pending") {
                        TokenBalance(amount: Self.amount(pending), symbol: symbol)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                PrivateBalanceActions(canMakePublic: model.availableLamports != nil)
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

    /// Shows lamports as SOL.
    /// - Parameter lamports: The lamports.
    /// - Returns: The amount in SOL's nine decimals.
    private static func amount(_ lamports: UInt64) -> Amount {
        Amount(units: lamports, decimals: 9)
    }
}
