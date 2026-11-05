import Foundation
import RPC

/// A service that looks up quotes for holdings and values them.
struct SnapshotPricer: Sendable {
    let provider: any PriceProviding

    /// Looks up quotes for holdings.
    ///
    /// - Parameter holdings: The holdings to price.
    /// - Returns: Quotes keyed by mint.
    /// - Throws: A provider or cancellation error.
    @concurrent
    func quotes(for holdings: [Holding.Identity]) async throws -> [String: Quote] {
        try Task.checkCancellation()
        return try await provider.prices(for: holdings.map { mint(for: $0) })
    }

    /// Returns a copy of a snapshot valued with the given quotes.
    ///
    /// - Parameters:
    ///   - snapshot: The snapshot to value.
    ///   - quotes: The quotes, keyed by mint.
    /// - Returns: The snapshot with new valuations.
    func snapshot(pricing snapshot: Snapshot, with quotes: [String: Quote]) -> Snapshot {
        var priced = snapshot
        for index in priced.holdings.indices {
            let holding = priced.holdings[index]
            guard let amount = holding.amount, let quote = quotes[mint(for: holding.id)] else {
                priced.holdings[index].valuation = nil
                continue
            }
            priced.holdings[index].valuation = Valuation(
                pricePerUnit: quote.pricePerUnit,
                total: total(for: amount, price: quote.pricePerUnit),
                currency: quote.currency,
                dayChange: quote.dayChange.flatMap { $0.isNaN ? nil : $0 })
        }
        return priced
    }

    /// Returns the mint whose quote prices a holding.
    ///
    /// - Parameter identity: The holding's identity.
    /// - Returns: The holding's mint, or Wrapped SOL's mint for native SOL.
    private func mint(for identity: Holding.Identity) -> String {
        switch identity {
        case .nativeSOL: "So11111111111111111111111111111111111111112"
        case .asset(let mint): mint
        }
    }

    /// Returns the exact value of an amount at a price.
    ///
    /// - Parameters:
    ///   - amount: The holding's amount.
    ///   - price: The price of one whole token.
    /// - Returns: The total, or `nil` if `Decimal` can't represent it.
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
