import SwiftUI

/// Opens the payment's review once the amount can be sent, also with Return on a hardware keyboard.
///
/// It reads whether the amount can be sent itself, so key presses update only this button.
struct SendButton: View {
    let payment: PaymentModel
    /// Opens the review of the typed amount.
    let send: SendPaymentAction

    var body: some View {
        Button("Send") { send() }
            .buttonStyle(.glassPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(!payment.canSend)
    }
}
