import SwiftUI

/// Shows the keypad of a balance move, and pushes its review.
struct BalanceMoveScreen: View {
    let move: BalanceMove
    /// The review that shows, or `nil` when none shows.
    @State private var presentedReview: TransactionReviewModel<BalanceMoveProposal>?
    /// The error that kept a review from starting.
    @State private var reviewError: PrivateBalanceError?

    var body: some View {
        PaymentAmountScreen(payment: move.payment,
                            title: move.direction.title(of: move.payment.token.asset.displaySymbol)) {
            let openReview = BalanceMoveReviewAction(move: move, presented: $presentedReview, error: $reviewError)
            Button("Review") { openReview() }
                .buttonStyle(.secondary)
                .keyboardShortcut(.defaultAction)
                .disabled(!move.payment.canSend)
        }
        .navigationDestination(item: $presentedReview) { review in
            TransactionReviewScreen<BalanceMoveReviewScreen, BalanceMoveResultScreen>(review: review)
        }
        .alert(error: $reviewError)
    }
}
