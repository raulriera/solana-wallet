import SwiftUI

/// Opens the payment's review once the amount can be sent, also with Return on a hardware keyboard.
///
/// It reads whether the amount can be sent itself, so key presses update only this button.
struct SendButton: View {
    let payment: PaymentModel
    /// Whether the review sheet is open.
    @Binding var isReviewing: Bool

    var body: some View {
        Button("Send") { isReviewing = true }
            .buttonStyle(.glassPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(!payment.canSend)
    }
}
