import SwiftUI

/// The line under the amount: what it comes to in the other unit, the balance when the person has nothing to choose,
/// or a warning when the amount is more than the balance; with a chevron when it opens the token and unit menu.
///
/// The warning replaces the line in the same place, so the amount never moves.
struct AmountCaption: View {
    @Environment(\.palette) private var palette
    let payment: PaymentModel

    var body: some View {
        let token = payment.token
        HStack(spacing: 6) {
            switch (payment.exceedsBalance, payment.unit, payment.value) {
            case (true, _, _):
                Text(payment.source.warning)
                    .foregroundStyle(.red)
                    // A sentence shrinks to fit instead of losing its middle words.
                    .minimumScaleFactor(0.5)
            case (false, .currency, _):
                Text(payment.quantity, format: .quantity(of: token))
            case (false, .token, let value?):
                Text(value, format: .value(code: payment.currencyCode))
            case (false, .token, nil) where payment.offersChoices:
                Text(token.symbol)
            case (false, .token, nil):
                Text(payment.source.balance(token.balance, of: token))
                    // Like the warning, the sentence shrinks to fit instead of losing its middle words.
                    .minimumScaleFactor(0.5)
            }
            if payment.offersChoices {
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
        }
        .font(.title3)
        // One line, so large text never pushes the keys down; long quantities lose their middle digits, keeping the
        // leading digits and the symbol.
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(palette.secondaryText)
        .contentTransition(.numericText())
        // The text and chevron stay together while the line's width changes.
        .geometryGroup()
    }
}
