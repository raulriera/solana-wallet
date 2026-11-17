import SwiftUI

/// Presents the keypad of a move of a token between the account's balances, and pushes its review.
struct BalanceMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let move: BalanceMove
    /// The review that shows, or `nil` when none shows.
    @State private var presentedReview: TransactionReviewModel<BalanceMoveProposal>?
    /// The error that kept a review from starting.
    @State private var reviewError: PrivateBalanceError?

    var body: some View {
        NavigationStack {
            PaymentAmountScreen(payment: move.payment,
                                title: move.direction.title(of: move.payment.token.asset.displaySymbol)) {
                let openReview = BalanceMoveReviewAction(move: move, presented: $presentedReview, error: $reviewError)
                Button("Review") { openReview() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!move.payment.canSend)
            }
            .cancellationAction()
            .navigationDestination(item: $presentedReview) { review in
                TransactionReviewScreen<BalanceMoveReviewScreen, BalanceMoveResultScreen>(review: review)
            }
        }
        .limitedTextSize()
        .environment(\.dismissParentContainer, dismiss)
        .alert(error: $reviewError)
    }
}
