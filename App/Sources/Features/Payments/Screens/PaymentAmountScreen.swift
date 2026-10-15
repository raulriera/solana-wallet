import SwiftUI

/// Types a payment's amount on an always-visible keypad, then opens its review.
///
/// The amount sits over the keypad, or beside it in short or clearly wide space, such as iPhone in landscape. A fold
/// across the screen splits them, so the keys stay on the flat half of iPhone Duo in a table pose.
struct PaymentAmountScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.locale) private var locale
    let payment: PaymentModel
    /// Whether the payment's review is open.
    @Binding var isReviewing: Bool

    var body: some View {
        ArrangementView {
            AmountColumn(payment: payment, isReviewing: $isReviewing)
        } secondary: {
            KeypadColumn(payment: payment, isReviewing: $isReviewing)
        }
        // Stacked, the keypad takes the height its keys use and the amount the rest. Below 720 pt the keys can't
        // reach their full size, so in clearly wide space the amount moves beside them; below 520 pt, any space wider
        // than tall does.
        .arrangementViewStyle(.adaptive(sideBySideAspectRatio: 1.25, fullStackedHeight: 720,
                                        minimumStackedHeight: 520))
        .background(palette.background)
        // Like a system keypad, the screen stops growing at the largest standard text size, so the keys keep their
        // layout; the keys show the large content viewer instead.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .navigationTitle("Send")
        .navigationBarTitleDisplayMode(.inline)
        // A hardware keyboard types on the keypad while the amount or any key has focus; held keys repeat.
        .onKeyPress(phases: [.down, .repeat], action: type)
    }

    /// Types digits, the decimal separator, and Delete from a hardware keyboard.
    /// - Parameter press: The key press.
    /// - Returns: Whether the screen handled the press.
    private func type(_ press: KeyPress) -> KeyPress.Result {
        let key: KeypadKey
        switch press.key {
        case .delete:
            key = .delete
        default:
            guard let typed = KeypadKey(typing: press.characters, locale: locale) else { return .ignored }
            key = typed
        }
        withAnimation(.snappy) { payment.press(key) }
        return .handled
    }
}

#if DEBUG
#Preview("Glass keys") {
    NavigationStack {
        PaymentAmountScreen(payment: PaymentModel(tokens: PaymentToken.samples, currencyCode: "USD"),
                            isReviewing: .constant(false))
    }
}

#Preview("Plain keys") {
    NavigationStack {
        PaymentAmountScreen(payment: PaymentModel(tokens: PaymentToken.samples, currencyCode: "USD"),
                            isReviewing: .constant(false))
            .keypadStyle(KeypadStyle(keyBackground: .none, amountLook: .plain))
    }
}
#endif
