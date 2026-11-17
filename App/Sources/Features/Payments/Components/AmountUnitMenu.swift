import SwiftUI

/// A menu that picks the token to pay with and the unit of the amount.
struct AmountUnitMenu<Label: View>: View {
    @Binding var token: PaymentToken
    @Binding var unit: PaymentModel.Unit
    let tokens: [PaymentToken]
    let currencyCode: String
    @ViewBuilder let label: Label

    var body: some View {
        Menu {
            Section("Pay With") {
                Picker("Token", selection: $token.animation(.snappy)) {
                    ForEach(tokens) { token in
                        Text(token.asset.displaySymbol)
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
                        Text(token.asset.displaySymbol)
                            .tag(PaymentModel.Unit.token)
                    }
                    .pickerStyle(.inline)
                }
            }
        } label: {
            label
        }
        .accessibilityValue(unit == .currency ? Text(token.asset.displaySymbol) : Text(verbatim: ""))
        .accessibilityHint(token.price == nil ? Text("Chooses the token.")
                                              : Text("Chooses the token and what you type the amount in."))
    }
}
