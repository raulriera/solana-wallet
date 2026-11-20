import SwiftUI
import Transactions

/// Shows the private balance's actions as button rows.
struct PrivateBalanceActions: View {
    @Environment(\.palette) private var palette
    @Environment(\.moveBalance) private var moveBalance
    @Environment(\.sendPrivately) private var sendPrivately
    /// The spendable private balance.
    let available: TokenAmount
    let asset: Asset

    var body: some View {
        Group {
            Button(
                BalanceMoveProposal.Direction.toPrivate.title(of: asset.displaySymbol),
                image: .customShieldBadgePlus
            ) {
                moveBalance?(.toPrivate)
            }
            if available.amount > 0 {
                Button(
                    BalanceMoveProposal.Direction.toPublic.title(of: asset.displaySymbol),
                    image: .customShieldBadgeMinus
                ) {
                    moveBalance?(.toPublic)
                }
                Button("Send Privately", systemImage: "paperplane") {
                    sendPrivately?()
                }
            }
        }
        .foregroundStyle(palette.primary)
        .lineLimit(1)
    }
}
