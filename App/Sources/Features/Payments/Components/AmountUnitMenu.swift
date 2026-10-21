import SwiftUI

/// The line under the amount, opening a menu to pick the token and the unit.
struct AmountUnitMenu: View {
    @Bindable var payment: PaymentModel

    var body: some View {
        let token = payment.token
        Menu {
            Section("Pay With") {
                Picker("Token", selection: $payment.tokenChoice.animation(.snappy)) {
                    ForEach(payment.tokens) { token in
                        Text(token.symbol)
                            .tag(token)
                    }
                }
                .pickerStyle(.inline)
            }
            if token.price != nil {
                Section("Type Amount In") {
                    Picker("Unit", selection: $payment.unitChoice.animation(.snappy)) {
                        Text(payment.currencyCode)
                            .tag(PaymentModel.Unit.currency)
                        Text(token.symbol)
                            .tag(PaymentModel.Unit.token)
                    }
                    .pickerStyle(.inline)
                }
            }
        } label: {
            AmountCaption(payment: payment)
        }
        // The unit choice is only there when the token has a price.
        .accessibilityHint(token.price == nil ? Text("Chooses the token.")
                                              : Text("Chooses the token and what you type the amount in."))
    }
}
