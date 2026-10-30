import SwiftUI

/// A button that opens the payment's review once the amount can be sent.
struct SendButton: View {
    let payment: PaymentModel
    let send: SendPaymentAction

    var body: some View {
        Button("Send") { send() }
            .buttonStyle(.glassPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(!payment.canSend)
    }
}
