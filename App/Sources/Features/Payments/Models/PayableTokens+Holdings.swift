import Portfolio

extension PayableTokens {
    /// The tokens that a portfolio's account can pay with: its holdings with a balance that the account controls, in the
    /// portfolio's order, priced in the currency of the portfolio's prices.
    ///
    /// Fails while the portfolio has nothing to show and no error.
    /// - Parameters:
    ///   - holdings: The portfolio's holdings in display order, or none before its first snapshot.
    ///   - error: Why the portfolio's latest update failed, or `nil` when it didn't.
    nonisolated init?(holdings: [Holding], error: PortfolioError?) {
        // A portfolio with data always lists SOL, so no holdings means it hasn't loaded, unless loading failed.
        guard !holdings.isEmpty || error != nil else { return nil }
        // A snapshot prices every holding in the person's chosen currency. Without any price, the keypad types tokens
        // and never shows a currency.
        let currencyCode = holdings.lazy.compactMap { $0.knownPrice?.currency }.first ?? "USD"
        self.init(tokens: holdings.compactMap { PaymentToken(holding: $0, currencyCode: currencyCode) },
                  currencyCode: currencyCode)
    }
}
