import SwiftUI

/// The line under the amount that shows its conversion, the balance, or a warning when it's more than the balance.
struct AmountCaption: View {
    @Environment(\.palette) private var palette
    let payment: PaymentModel

    var body: some View {
        let token = payment.token
        HStack(spacing: 6) {
            switch (payment.exceedsBalance, payment.unit, payment.value) {
            case (true, _, _):
                Text(payment.source.warning)
                    .foregroundStyle(palette.destructive)
                    .minimumScaleFactor(0.5)
            case (false, .currency, _):
                Text(payment.quantity, format: .quantity(of: token))
            case (false, .token, let value?):
                Text(value, format: .value(code: payment.currencyCode))
            case (false, .token, nil) where payment.offersChoices:
                Text(token.symbol)
            case (false, .token, nil):
                Text(payment.source.balance(token.balance, of: token))
                    .minimumScaleFactor(0.5)
            }
            if payment.offersChoices {
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
        }
        .font(.title3)
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(palette.secondaryText)
        .contentTransition(.numericText())
        .geometryGroup()
    }
}
