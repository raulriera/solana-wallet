extension PortfolioCoordinating {
    /// The tokens that the portfolio's account can pay with, priced in the currency of the portfolio's prices.
    /// - Returns: The tokens with a balance that the account controls, in the portfolio's order, and their prices'
    ///   currency; or `nil` while the portfolio has nothing to show and no error.
    func payableTokens() -> PayableTokens? {
        // A portfolio with data always lists SOL, so no holdings means it hasn't loaded, unless loading failed.
        guard !holdings.isEmpty || error != nil else { return nil }
        // A snapshot prices every holding in the person's chosen currency. Without any price, the keypad types tokens
        // and never shows a currency.
        let currencyCode = holdings.lazy.compactMap { $0.knownPrice?.currency }.first ?? "USD"
        return PayableTokens(tokens: holdings.compactMap { PaymentToken(holding: $0, currencyCode: currencyCode) },
                             currencyCode: currencyCode)
    }
}
