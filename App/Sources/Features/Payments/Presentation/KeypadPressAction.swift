/// An action that types a key into a payment's amount.
struct KeypadPressAction {
    let payment: PaymentModel

    /// Types a key into the amount.
    ///
    /// - Parameter key: The pressed key.
    func callAsFunction(_ key: KeypadKey) {
        payment.press(key)
    }
}
