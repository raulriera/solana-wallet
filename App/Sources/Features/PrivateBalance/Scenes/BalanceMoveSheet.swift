import SwiftUI

/// Presents a move of SOL between the account's balances in its own navigation container: the keypad, with the review
/// in a sheet over it.
///
/// Review opens the review at once, which proves and simulates the move while it shows. Cancel closes the keypad's
/// sheet. Once the move is approved, it can't be reviewed again, so the keypad closes once its review closes; the shared
/// transactions keep sending and watching it. A dropped move keeps its amount.
struct BalanceMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let move: BalanceMove
    /// The latest review, which stays after its sheet closes.
    @State private var review: TransactionReviewModel<BalanceMoveProposal>?
    /// The review that shows, or `nil` while none does.
    @State private var presentedReview: TransactionReviewModel<BalanceMoveProposal>?
    /// Why a review couldn't start.
    @State private var reviewError: PrivateBalanceError?
    /// Matches the Review button with the review, which grows out of it.
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
                // The review grows out of the Review button, and shrinks back into it when canceled.
                .navigationTransition(.zoom(sourceID: move.id, in: reviewTransition))
        }
        // A committed move used up its amount, so the keypad closes once its review closes, also while the move is
        // still being sent; after a drop, the amount stays to review again.
        .onChange(of: presentedReview == nil && review?.isCommitted == true) { _, isCommittedAndClosed in
            if isCommittedAndClosed { dismiss() }
        }
        .errorAlert($reviewError)
    }
}
