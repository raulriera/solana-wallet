import SwiftUI

/// The amount's region of the keypad screen, with Send under it when the keypad sits beside it.
struct AmountColumn: View {
    @Environment(\.arrangementAxis) private var axis
    let payment: PaymentModel
    /// Whether the review sheet is open.
    @Binding var isReviewing: Bool

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                AmountSummary(payment: payment)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .scrollBounceBehavior(.basedOnSize)
            // Stacked, the amount keeps its full height and the keypad gives up height first; beside the keypad, the
            // amount scrolls when large text outgrows the column.
            .fixedSize(horizontal: false, vertical: axis == .vertical)
            // The amount centers in the height it has. Stacked, it takes at most the height it uses on iPhone, so in
            // taller space it stays with the keypad instead of floating above it.
            .frame(maxHeight: axis == .vertical ? 280 : .infinity)
            // Beside the keypad, Send stays with the amount, up to the keys' widest, so the keys keep the full height.
            if axis == .horizontal {
                SendButton(payment: payment, isReviewing: $isReviewing)
                    .fractionalWidth(0.75, maximum: 386)
                    .padding(.vertical)
                    // Send moves to the other region when the layout changes, so it fades between them.
                    .transition(.opacity.animation(.snappy))
            }
        }
    }
}
