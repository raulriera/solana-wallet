/// Types a key into the payment's amount from any key on the keypad, the way SwiftUI's `dismiss` acts for the view
/// that reads it.
struct KeypadPressAction {
    /// The payment the keys type into.
    let payment: PaymentModel

    /// Types a key; a rejected key leaves the amount as it was.
    /// - Parameter key: The pressed key.
    func callAsFunction(_ key: KeypadKey) {
        payment.press(key)
    }
}
