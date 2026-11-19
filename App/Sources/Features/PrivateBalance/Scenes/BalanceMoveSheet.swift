import SwiftUI

/// Presents the keypad of a move of a token between the account's balances, and pushes its review.
struct BalanceMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let move: BalanceMove

    var body: some View {
        NavigationStack {
            BalanceMoveScreen(move: move)
                .cancellationAction()
        }
        .limitedTextSize()
        .environment(\.dismissParentContainer, dismiss)
    }
}
