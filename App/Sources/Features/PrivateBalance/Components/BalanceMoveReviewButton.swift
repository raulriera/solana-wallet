import SwiftUI

/// Opens the move's review once the amount can be moved, also with Return on a hardware keyboard.
///
/// It reads whether the amount can be moved itself, so key presses update only this button.
struct BalanceMoveReviewButton: View {
    let payment: PaymentModel
    /// Opens the review of the typed amount.
    let review: BalanceMoveReviewAction

    var body: some View {
        Button("Review") { review() }
            .buttonStyle(.glassPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(!payment.canSend)
    }
}
