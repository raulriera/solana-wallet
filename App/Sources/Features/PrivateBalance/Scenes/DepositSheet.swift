import SwiftUI

/// Presents a deposit in its own navigation container: the keypad, with the review in a sheet over it.
///
/// Cancel closes the sheet; the review's result closes both.
struct DepositSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Matches the Review button with the review, which grows out of it.
    @Namespace private var review
    @Bindable var deposit: DepositModel

    var body: some View {
        NavigationStack {
            PaymentAmountScreen(payment: deposit.payment, title: "Add to Private Balance") {
                DepositReviewButton(deposit: deposit)
                    .matchedTransitionSource(id: deposit.id, in: review)
            }
            // The keys stay as typed while the deposit is prepared.
            .disabled(deposit.isWorking)
            .cancellationAction()
        }
        .sheet(isPresented: $deposit.isReviewing) {
            DepositReviewSheet(deposit: deposit, close: dismiss)
                // The review grows out of the Review button, and shrinks back into it when canceled.
                .navigationTransition(.zoom(sourceID: deposit.id, in: review))
        }
    }
}
