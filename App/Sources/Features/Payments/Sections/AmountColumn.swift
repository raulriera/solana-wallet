import SwiftUI

/// The amount's region of the keypad screen, which scrolls when large text outgrows it.
struct AmountColumn: View {
    let payment: PaymentModel

    var body: some View {
        ScrollView {
            AmountSummary(payment: payment)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
    }
}
