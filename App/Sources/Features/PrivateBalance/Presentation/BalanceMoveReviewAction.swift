import SwiftUI

/// Opens the review of a balance move's typed amount.
struct BalanceMoveReviewAction {
    let move: BalanceMove
    /// The latest review, including one whose sheet closed.
    let review: Binding<TransactionReviewModel<BalanceMoveProposal>?>
    /// The review that shows, or `nil` when none shows.
    let presented: Binding<TransactionReviewModel<BalanceMoveProposal>?>
    /// The error that kept a review from starting.
    let error: Binding<PrivateBalanceError?>

    /// Opens and prepares a review of the typed amount, unless one shows or the amount can't be moved.
    func callAsFunction() {
        guard presented.wrappedValue == nil, move.payment.canSend else { return }
        do {
            let model = try move.review()
            model.prepareReview()
            review.wrappedValue = model
            presented.wrappedValue = model
        } catch {
            self.error.wrappedValue = .preparationFailed
        }
    }
}
