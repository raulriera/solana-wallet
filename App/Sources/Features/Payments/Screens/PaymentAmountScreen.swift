import SwiftUI
import Transactions

/// Types a payment's amount on an always-visible keypad, then commits it with the caller's button, such as Send.
///
/// The amount sits beside the keypad in space wider than tall, such as iPhone in landscape, and over it otherwise.
/// The button stays under the keys, or under the amount beside them, at the keys' width. A fold across the screen
/// splits them, so the keys stay on the flat half of iPhone Duo in a table pose.
struct PaymentAmountScreen<Action: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.locale) private var locale
    let payment: PaymentModel
    /// The screen's title, such as Send or the recipient's name.
    let title: Text
    /// The line under the title, such as a named recipient's short address, or empty for none.
    let subtitle: Text
    /// The button that commits the amount, under the keys.
    let action: Action

    /// Creates the keypad screen for a payment.
    /// - Parameters:
    ///   - payment: The payment whose amount the keys type.
    ///   - title: The screen's title, such as Send.
    ///   - action: The button that commits the amount, which reads whether the amount can be committed itself.
    init(payment: PaymentModel, title: LocalizedStringResource, @ViewBuilder action: () -> Action) {
        self.payment = payment
        self.title = Text(title)
        subtitle = Text(verbatim: "")
        self.action = action()
    }

    /// Creates the keypad screen for a payment to a recipient, titled with their name or short address.
    /// - Parameters:
    ///   - payment: The payment whose amount the keys type.
    ///   - recipient: Who the payment goes to; a named recipient shows their short address under the name.
    ///   - action: The button that commits the amount, which reads whether the amount can be committed itself.
    init(payment: PaymentModel, recipient: PaymentRecipient, @ViewBuilder action: () -> Action) {
        self.payment = payment
        title = Text(verbatim: recipient.title)
        subtitle = Text(verbatim: recipient.name == nil ? "" : recipient.address.formatted(.shortAddress))
        self.action = action()
    }

    var body: some View {
        ArrangementView {
            AmountColumn(payment: payment)
        } secondary: {
            Keypad()
                // The keys keep the system's spacing from the amount above them and from the button below them.
                .padding(.vertical)
                .environment(\.pressKey, KeypadPressAction(payment: payment))
            action
        }
        .arrangementViewStyle(.adaptive)
        .contentMargins(for: .container)
        // The button keeps the system's spacing from the tab bar below it.
        .scenePadding(.bottom)
        .background(palette.background)
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
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
    let payment = PaymentModel(tokens: PaymentToken.samples, currencyCode: "USD")
    NavigationStack {
        PaymentAmountScreen(payment: payment, title: "Send") {
            SendButton(payment: payment, isReviewing: .constant(false))
        }
    }
}

#Preview("Plain keys") {
    let payment = PaymentModel(tokens: PaymentToken.samples, currencyCode: "USD")
    NavigationStack {
        PaymentAmountScreen(payment: payment, title: "Send") {
            SendButton(payment: payment, isReviewing: .constant(false))
        }
        .keypadStyle(KeypadStyle(keyBackground: .none, amountLook: .plain))
    }
}

#Preview("One balance") {
    let payment = PaymentModel(tokens: [PaymentToken(symbol: "SOL", balance: Decimal(string: "1.2")!, price: nil,
                                                     decimals: 9)],
                               currencyCode: "USD", source: .publicBalance)
    NavigationStack {
        PaymentAmountScreen(payment: payment, title: "Make SOL Private") {
            SendButton(payment: payment, isReviewing: .constant(false))
        }
    }
}
#endif
