import SwiftUI

/// Opens the review of a move's typed amount from the button under its keypad, the way SwiftUI's `dismiss` acts for the
/// view that reads it.
struct BalanceMoveReviewAction {
    /// The move whose typed amount is reviewed.
    let move: BalanceMove
    /// The latest review, which stays after it closes.
    let review: Binding<TransactionReviewModel<BalanceMoveProposal>?>
    /// The review that shows, or `nil` while none does.
    let presented: Binding<TransactionReviewModel<BalanceMoveProposal>?>
    /// Why a review couldn't start.
    let error: Binding<PrivateBalanceError?>

    /// Opens a review of the typed amount and starts proving and simulating it; nothing opens while the amount can't be
    /// moved or a review shows.
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
