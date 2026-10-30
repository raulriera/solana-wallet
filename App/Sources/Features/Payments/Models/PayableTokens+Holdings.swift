import Portfolio

extension PayableTokens {
    /// Creates the tokens of a portfolio's holdings, or `nil` while the portfolio has nothing to show and no error.
    ///
    /// - Parameters:
    ///   - holdings: The portfolio's holdings in display order.
    ///   - error: The error of the portfolio's latest update, or `nil` when it succeeded.
    nonisolated init?(holdings: [Holding], error: PortfolioError?) {
        guard !holdings.isEmpty || error != nil else { return nil }
        let currencyCode = holdings.lazy.compactMap { $0.knownPrice?.currency }.first ?? "USD"
        self.init(tokens: holdings.compactMap { PaymentToken(holding: $0, currencyCode: currencyCode) },
                  currencyCode: currencyCode)
    }
}
