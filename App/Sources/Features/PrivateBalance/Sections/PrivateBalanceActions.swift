import Portfolio
import SwiftUI

/// Shows the private balance's actions as button rows.
struct PrivateBalanceActions: View {
    @Environment(\.palette) private var palette
    @Environment(\.moveBalance) private var moveBalance
    /// The spendable private balance.
    let available: Amount
    let symbol: String

    var body: some View {
        Group {
            Button(BalanceMoveProposal.Direction.toPrivate.title(of: symbol), systemImage: "eye.slash") {
                moveBalance?(.toPrivate)
            }
            if available.units > 0 {
                Button(BalanceMoveProposal.Direction.toPublic.title(of: symbol), systemImage: "eye") {
                    moveBalance?(.toPublic)
                }
            }
        }
        .foregroundStyle(palette.primary)
        .lineLimit(1)
    }
}
