import SwiftUI

/// Presents the keypad of a move of SOL between the account's balances, with its review in a sheet.
struct BalanceMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let move: BalanceMove
    /// The latest review, including one whose sheet closed.
    @State private var review: TransactionReviewModel<BalanceMoveProposal>?
    /// The review that shows, or `nil` when none shows.
    @State private var presentedReview: TransactionReviewModel<BalanceMoveProposal>?
    /// The error that kept a review from starting.
    @State private var reviewError: PrivateBalanceError?
    @Namespace private var reviewTransition

    var body: some View {
        NavigationStack {
            PaymentAmountScreen(payment: move.payment, title: move.direction.title) {
                BalanceMoveReviewButton(payment: move.payment,
                                        review: BalanceMoveReviewAction(move: move, review: $review,
                                                                        presented: $presentedReview,
                                                                        error: $reviewError))
                    .matchedTransitionSource(id: move.id, in: reviewTransition)
            }
            .cancellationAction()
        }
        .limitedTextSize()
        .sheet(item: $presentedReview) { review in
            TransactionReviewSheet<BalanceMoveReviewScreen, BalanceMoveResultScreen>(review: review)
                .transactionReviewLifecycle()
                .navigationTransition(.zoom(sourceID: move.id, in: reviewTransition))
        }
        .onChange(of: presentedReview == nil && review?.isCommitted == true) { _, isCommittedAndClosed in
            if isCommittedAndClosed { dismiss() }
        }
        .alert(error: $reviewError)
    }
}
