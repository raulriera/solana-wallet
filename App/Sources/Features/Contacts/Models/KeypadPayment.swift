/// What the contacts tab's keypad pays with, as the window's portfolio loads.
enum KeypadPayment {
    /// The portfolio has nothing to show yet.
    case loading
    /// The account has no token with a balance.
    case nothingToSend
    /// The payment being typed, which stays when the person picks another recipient.
    case ready(PaymentModel)

    /// The payment being typed, or `nil` when there's nothing to pay with yet.
    var model: PaymentModel? {
        guard case .ready(let model) = self else { return nil }
        return model
    }

    /// Whether the portfolio has nothing to show yet.
    var isLoading: Bool {
        guard case .loading = self else { return false }
        return true
    }
}
