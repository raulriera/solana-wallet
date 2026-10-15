import SwiftUI

/// The line under the amount: what it comes to in the other unit, or a warning when it's more than the balance,
/// opening a menu to pick the token and the unit.
///
/// The warning replaces the conversion on the same line, so the amount never moves.
struct AmountUnitMenu: View {
    @Environment(\.palette) private var palette
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
            HStack(spacing: 6) {
                switch (payment.exceedsBalance, payment.unit, payment.value) {
                case (true, _, _):
                    Text("More than your balance")
                        .foregroundStyle(.red)
                        // A sentence shrinks to fit instead of losing its middle words.
                        .minimumScaleFactor(0.5)
                case (false, .currency, _):
                    Text(payment.quantity, format: .quantity(of: token))
                case (false, .token, let value?):
                    Text(value, format: .value(code: payment.currencyCode))
                case (false, .token, nil):
                    Text(token.symbol)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(.title3)
            // One line, so large text never pushes the keys down; long quantities lose their middle digits, keeping
            // the leading digits and the symbol.
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(palette.secondaryText)
            .contentTransition(.numericText())
            // The amount and chevron stay together while the label's width changes.
            .geometryGroup()
        }
        // The unit choice is only there when the token has a price.
        .accessibilityHint(token.price == nil ? Text("Chooses the token.")
                                              : Text("Chooses the token and what you type the amount in."))
    }
}
