import SwiftUI

/// Presents a move of SOL between the account's balances in its own navigation container: the keypad, with the review
/// in a sheet over it.
///
/// Cancel closes the sheet; the review's result closes both.
struct BalanceMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Matches the Review button with the review, which grows out of it.
    @Namespace private var review
    @Bindable var move: BalanceMoveModel

    var body: some View {
        NavigationStack {
            PaymentAmountScreen(payment: move.payment, title: move.direction.title) {
                BalanceMoveReviewButton(move: move)
                    .matchedTransitionSource(id: move.id, in: review)
                    .environment(\.reviewMove, BalanceMoveReviewAction(move: move))
            }
            // The keys stay as typed while the move is prepared.
            .disabled(move.isWorking)
            .cancellationAction()
        }
        .limitedTextSize()
        .sheet(isPresented: $move.isReviewing) {
            BalanceMoveReviewSheet(move: move, close: dismiss)
                // The review grows out of the Review button, and shrinks back into it when canceled.
                .navigationTransition(.zoom(sourceID: move.id, in: review))
        }
    }
}
