import SwiftUI

/// The keypad's region of the keypad screen, with Send under the keys when the amount sits above them.
///
/// The keys and Send span three quarters of the region's width, up to the keys' widest, so the keys keep the Phone
/// keypad's proportions on iPhone and grow with wider space.
struct KeypadColumn: View {
    @Environment(\.arrangementAxis) private var axis
    let payment: PaymentModel
    /// Whether the review sheet is open.
    @Binding var isReviewing: Bool

    var body: some View {
        VStack(spacing: 20) {
            Keypad(payment: payment)
            if axis == .vertical {
                SendButton(payment: payment, isReviewing: $isReviewing)
                    // Send moves to the other region when the layout changes, so it fades between them.
                    .transition(.opacity.animation(.snappy).combined(with: .scale(0.75)))
            }
        }
        // At most the keys' widest, three 110 pt keys and two 28 pt gaps, so Send matches the keys.
        .fractionalWidth(0.75, maximum: 386)
        .padding(.vertical, 8)
        // Stacked, the keypad takes only the height its keys use; beside the amount, it centers in the full height.
        .frame(maxHeight: axis == .horizontal ? .infinity : nil)
    }
}
