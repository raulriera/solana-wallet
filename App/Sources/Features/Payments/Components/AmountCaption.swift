import SwiftUI

/// The line under the amount that shows the balance in the amount's unit, or a warning when the amount is more than it.
struct AmountCaption: View {
    @Environment(\.palette) private var palette
    let payment: PaymentModel

    var body: some View {
        let exceedsBalance = payment.exceedsBalance
        HStack(spacing: 6) {
            Text(exceedsBalance ? payment.source.warning : payment.balanceText)
                .foregroundStyle(exceedsBalance ? palette.destructive : palette.secondaryText)
            if payment.offersChoices {
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
        }
        .font(.title3)
        .minimumScaleFactor(0.5)
        .lineLimit(1, reservesSpace: true)
        .truncationMode(.middle)
        .foregroundStyle(palette.secondaryText)
        .contentTransition(.numericText())
        .geometryGroup()
    }
}
