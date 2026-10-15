import Foundation
import RPC

/// Looks up quotes for a balance read's holdings and values them.
struct SnapshotPricer: Sendable {
    let provider: any PriceProviding

    /// Looks up quotes for holdings; the provider looks up a market that two holdings share once.
    /// - Parameter holdings: The holdings to price; native SOL shares Wrapped SOL's market.
    /// - Returns: Quotes keyed by mint; a mint without a quote has no entry.
    /// - Throws: A provider or cancellation error.
    @concurrent
    func quotes(for holdings: [Holding.Identity]) async throws -> [String: Quote] {
        try Task.checkCancellation()
        return try await provider.prices(for: holdings.map { mint(for: $0) })
    }

    /// Replaces all valuations with looked-up quotes.
    /// - Parameters:
    ///   - snapshot: The complete holdings to value.
    ///   - quotes: The quotes from ``quotes(for:)``, keyed by mint.
    /// - Returns: The same holdings with new valuations; omitted quotes remain unknown.
    /// - Throws: `PriceError.invalidQuote` for an invalid price or currency.
    func snapshot(pricing snapshot: Snapshot, with quotes: [String: Quote]) throws -> Snapshot {
        var priced = snapshot
        for index in priced.holdings.indices {
            let holding = priced.holdings[index]
            guard let quote = quotes[mint(for: holding.id)] else {
                priced.holdings[index].valuation = nil
                continue
            }
            guard !quote.pricePerUnit.isNaN, quote.pricePerUnit >= 0,
                  !quote.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PriceError.invalidQuote
            }
            priced.holdings[index].valuation = Valuation(
                pricePerUnit: quote.pricePerUnit,
                total: holding.amount.flatMap { total(for: $0, price: quote.pricePerUnit) },
                currency: quote.currency,
                // A change that isn't a number stays unknown; the price is still valid.
                dayChange: quote.dayChange.flatMap { $0.isNaN ? nil : $0 })
        }
        return priced
    }

    /// Identifies the token market for a holding without merging native SOL and Wrapped SOL balances.
    /// - Parameter identity: The holding's identity.
    /// - Returns: The quote mint, shared by native SOL and Wrapped SOL.
    private func mint(for identity: Holding.Identity) -> String {
        switch identity {
        case .nativeSOL: "So11111111111111111111111111111111111111112"
        case .asset(let mint): mint
        }
    }

    /// Multiplies exact token units by a decimal quote without binary floating-point conversion.
    /// - Parameters:
    ///   - amount: The holding's integer units and decimal scale.
    ///   - price: The nonnegative price of one whole token.
    /// - Returns: The exact decimal total, or `nil` if Decimal cannot represent the calculation.
    private func total(for amount: Amount, price: Decimal) -> Decimal? {
        if amount.units == 0 || price == 0 { return 0 }
        var units = Decimal(amount.units)
        var quantity = Decimal()
        guard NSDecimalMultiplyByPowerOf10(&quantity, &units, -Int16(amount.decimals), .plain) == .noError else { return nil }
        var price = price
        var total = Decimal()
        guard NSDecimalMultiply(&total, &quantity, &price, .plain) == .noError else { return nil }
        return total
    }
}
