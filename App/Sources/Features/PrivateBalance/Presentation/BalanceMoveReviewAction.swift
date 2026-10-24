/// Reviews a move's typed amount from the button under its keypad, the way SwiftUI's `dismiss` acts for the view that
/// reads it.
struct BalanceMoveReviewAction {
    /// The move whose typed amount is reviewed.
    let move: BalanceMoveModel

    /// Starts preparing the review; nothing starts while the amount can't be moved or the move is already working.
    func callAsFunction() {
        move.prepareReview()
    }
}
