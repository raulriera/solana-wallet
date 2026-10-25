/// The tokens an account can pay with, and the currency their prices are in.
nonisolated struct PayableTokens: Equatable, Sendable {
    /// The tokens with a balance that the account controls, in the portfolio's order.
    let tokens: [PaymentToken]
    /// The ISO code of the currency that the tokens' prices are in.
    let currencyCode: String
}
