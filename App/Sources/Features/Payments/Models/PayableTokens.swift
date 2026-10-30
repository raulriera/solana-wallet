/// The tokens an account can pay with, and the currency their prices are in.
nonisolated struct PayableTokens: Equatable, Sendable {
    let tokens: [PaymentToken]
    /// The code of the currency that the tokens' prices are in.
    let currencyCode: String
}
