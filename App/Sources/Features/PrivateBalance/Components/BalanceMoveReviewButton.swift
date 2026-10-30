import SwiftUI

/// Opens a balance move's review once the amount can be moved.
struct BalanceMoveReviewButton: View {
    let payment: PaymentModel
    let review: BalanceMoveReviewAction

    var body: some View {
        Button("Review") { review() }
            .buttonStyle(.glassPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(!payment.canSend)
    }
}
