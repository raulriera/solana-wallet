import SwiftUI
import Transactions

/// Types a payment's amount on a keypad and commits it with a button, such as Send.
struct PaymentAmountScreen<Action: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.locale) private var locale
    let payment: PaymentModel
    let title: Text
    let subtitle: Text
    let action: Action

    /// Creates the keypad screen for a payment.
    ///
    /// - Parameters:
    ///   - payment: The payment whose amount the keys type.
    ///   - title: The screen's title, such as Send.
    ///   - action: The button that commits the amount.
    init(payment: PaymentModel, title: LocalizedStringResource, @ViewBuilder action: () -> Action) {
        self.payment = payment
        self.title = Text(title)
        subtitle = Text(verbatim: "")
        self.action = action()
    }

    /// Creates the keypad screen for a payment to a recipient, titled with their name or short address.
    ///
    /// - Parameters:
    ///   - payment: The payment whose amount the keys type.
    ///   - recipient: The recipient of the payment.
    ///   - action: The button that commits the amount.
    init(payment: PaymentModel, recipient: PaymentRecipient, @ViewBuilder action: () -> Action) {
        self.payment = payment
        title = Text(verbatim: recipient.title)
        subtitle = Text(verbatim: recipient.subtitle)
        self.action = action()
    }

    var body: some View {
        ArrangementView {
            AmountColumn(payment: payment)
        } secondary: {
            Keypad()
                .padding(.vertical)
                .environment(\.pressKey, KeypadPressAction(payment: payment))
            action
        }
        .arrangementViewStyle(.adaptive)
        .contentMargins(for: .container)
        .scenePadding(.bottom)
        .background(palette.background)
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .onKeyPress(phases: [.down, .repeat], action: type)
    }

    /// Types digits, the decimal separator, and Delete from a hardware keyboard.
    ///
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

#Preview("Glass keys") {
    let payment = PaymentModel(tokens: [PaymentToken(mint: nil, symbol: "SOL", balance: 1.2,
                                                     price: 150, decimals: 9)],
                               currencyCode: "USD")
    NavigationStack {
        PaymentAmountScreen(payment: payment, title: "Send") {
            Button("Send") {}
                .buttonStyle(.glassPrimary)
        }
    }
}

#Preview("Plain keys") {
    let payment = PaymentModel(tokens: [PaymentToken(mint: nil, symbol: "SOL", balance: 1.2,
                                                     price: 150, decimals: 9)],
                               currencyCode: "USD")
    NavigationStack {
        PaymentAmountScreen(payment: payment, title: "Send") {
            Button("Send") {}
                .buttonStyle(.glassPrimary)
        }
        .keypadStyle(KeypadStyle(keyBackground: .none, amountLook: .plain))
    }
}

#Preview("One balance") {
    let payment = PaymentModel(tokens: [PaymentToken(mint: nil, symbol: "SOL", balance: 1.2,
                                                     price: nil, decimals: 9)],
                               currencyCode: "USD", source: .publicBalance)
    NavigationStack {
        PaymentAmountScreen(payment: payment, title: "Make SOL Private") {
            Button("Send") {}
                .buttonStyle(.glassPrimary)
        }
    }
}
