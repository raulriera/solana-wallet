import SwiftUI

/// The line under the amount, opening a menu to pick the token and the unit.
struct AmountUnitMenu<Label: View>: View {
    /// The token to pay with.
    @Binding var token: PaymentToken
    /// The unit the amount is typed in.
    @Binding var unit: PaymentModel.Unit
    /// The tokens the account can pay with.
    let tokens: [PaymentToken]
    /// The ISO code of the person's currency.
    let currencyCode: String
    /// The line the menu opens from.
    @ViewBuilder let label: Label

    var body: some View {
        Menu {
            Section("Pay With") {
                Picker("Token", selection: $token.animation(.snappy)) {
                    ForEach(tokens) { token in
                        Text(token.symbol)
                            .tag(token)
                    }
                }
                .pickerStyle(.inline)
            }
            if token.price != nil {
                Section("Type Amount In") {
                    Picker("Unit", selection: $unit.animation(.snappy)) {
                        Text(currencyCode)
                            .tag(PaymentModel.Unit.currency)
                        Text(token.symbol)
                            .tag(PaymentModel.Unit.token)
                    }
                    .pickerStyle(.inline)
                }
            }
        } label: {
            label
        }
        // The unit choice is only there when the token has a price.
        .accessibilityHint(token.price == nil ? Text("Chooses the token.")
                                              : Text("Chooses the token and what you type the amount in."))
    }
}
