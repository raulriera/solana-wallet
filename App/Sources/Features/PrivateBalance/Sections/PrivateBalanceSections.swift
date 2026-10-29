import Portfolio
import SwiftUI

/// The private balance of SOL's details: Turn On while private balances are off, then the available and pending SOL,
/// with the actions as rows under them.
///
/// Nothing shows before the first read, or where private balances aren't available, so the sections animate in. After
/// a failed read, the footer says that the balance couldn't update and the actions are disabled; without a balance to
/// show, only the footer shows.
struct PrivateBalanceSections: View {
    @Environment(\.palette) private var palette
    /// Whether an attempt to turn private balances on is waiting or running.
    let isTurningOn: Bool
    /// Turns private balances on.
    let turnOn: PrivateBalanceTurnOnAction
    /// The account's last read or saved private balance, or `nil` before the first read.
    let status: PrivateBalanceStatus?
    /// Whether the last read failed, so ``status`` may be out of date.
    let isOutdated: Bool
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
        // `where` covers only `nil`: after a failed first read without saved notes, the section still shows its footer.
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
                        // Every move reads the private balance first, so none can work until a read succeeds.
                        .disabled(isOutdated)
                }
            } header: {
                Text("Private Balance")
            } footer: {
                Group {
                    if isOutdated {
                        Text("Couldn't update private balance.",
                             comment: "Footer under a private balance that the last read couldn't update, such as when the provider fails. The balance shown is the last one read or saved, if any.")
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

    /// The available and pending SOL to show, in lamports: none yet for an unregistered account, and `nil` without a
    /// balance, such as after a failed first read without saved notes.
    private var lamports: (available: UInt64, pending: UInt64)? {
        switch status {
        case .balance(let available, let pending)?: (available, pending)
        case .unregistered?: (0, 0)
        case .off?, .unavailable?, nil: nil
        }
    }
}
