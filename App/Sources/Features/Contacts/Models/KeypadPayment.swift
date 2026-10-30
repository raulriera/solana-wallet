/// The state of the keypad's payment as the portfolio loads.
enum KeypadPayment {
    case loading
    /// The account has no token with a balance.
    case nothingToSend
    /// The payment being typed.
    case ready(PaymentModel)

    /// The payment being typed, or `nil` when there's nothing to pay with.
    var model: PaymentModel? {
        guard case .ready(let model) = self else { return nil }
        return model
    }

    var isLoading: Bool {
        guard case .loading = self else { return false }
        return true
    }
}
