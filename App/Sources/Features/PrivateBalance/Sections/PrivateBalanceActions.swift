import SwiftUI
import Transactions

/// Shows the private balance's actions as button rows.
struct PrivateBalanceActions: View {
    @Environment(\.palette) private var palette
    @Environment(\.moveBalance) private var moveBalance
    /// The spendable private balance.
    let available: TokenAmount
    let asset: Asset

    var body: some View {
        Group {
            Button(BalanceMoveProposal.Direction.toPrivate.title(of: asset.displaySymbol), systemImage: "eye.slash") {
                moveBalance?(.toPrivate)
            }
            if available.amount > 0 {
                Button(BalanceMoveProposal.Direction.toPublic.title(of: asset.displaySymbol), systemImage: "eye") {
                    moveBalance?(.toPublic)
                }
            }
        }
        .foregroundStyle(palette.primary)
        .lineLimit(1)
    }
}
