import Foundation
import RPC

/// Looks up quotes for a balance read's holdings and values them.
struct SnapshotPricer: Sendable {
    let provider: any PriceProviding
    private let now: @Sendable () -> Date

    /// Creates a pricer that records when each lookup completes.
    /// - Parameters:
    ///   - provider: The source of normalized quotes for these holdings.
    ///   - now: The clock used to record successful lookup completion.
    init(provider: any PriceProviding, now: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.now = now
    }

    /// Checks that prices describe the same network as the wallet's holdings.
    /// - Parameter network: The network whose holdings are being refreshed.
    /// - Throws: `PriceError.networkMismatch` for a different price-provider network.
    func validate(network: Network) throws {
        guard provider.network == network else { throw PriceError.networkMismatch }
    }

    /// Looks up quotes for holdings, once for each market.
    /// - Parameter holdings: The holdings to price; native SOL shares Wrapped SOL's market.
    /// - Returns: Quotes keyed by mint; a mint without a quote has no entry.
    /// - Throws: A provider or cancellation error.
    @concurrent
    func quotes(for holdings: [Holding.Identity]) async throws -> [String: Quote] {
        try Task.checkCancellation()
        var seen: Set<String> = []
        let mints = holdings.map { mint(for: $0) }.filter { seen.insert($0).inserted }
        return try await provider.prices(for: mints)
    }

    /// Replaces all valuations with looked-up quotes while preserving the holdings' retrieval time.
    /// - Parameters:
    ///   - snapshot: The complete holdings to value.
    ///   - quotes: The quotes from ``quotes(for:)``, keyed by mint.
    /// - Returns: The same holdings with new valuations; omitted quotes remain unknown.
    /// - Throws: `PriceError.invalidQuote` for an invalid price, currency, or retrieval time.
    func snapshot(pricing snapshot: Snapshot, with quotes: [String: Quote]) throws -> Snapshot {
        let holdings = try snapshot.holdings.map { holding in
            let valuation: Valuation?
            if let quote = quotes[mint(for: holding.id)] {
                guard !quote.pricePerUnit.isNaN, quote.pricePerUnit >= 0,
                      !quote.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      quote.fetchedAt.timeIntervalSinceReferenceDate.isFinite else { throw PriceError.invalidQuote }
                valuation = Valuation(pricePerUnit: quote.pricePerUnit,
                                      total: holding.amount.flatMap { total(for: $0, price: quote.pricePerUnit) },
                                      currency: quote.currency, fetchedAt: quote.fetchedAt,
                                      // A change that isn't a number stays unknown; the price is still valid.
                                      dayChange: quote.dayChange.flatMap { $0.isNaN ? nil : $0 })
            } else {
                valuation = nil
            }
            return Holding(id: holding.id, amount: holding.amount, name: holding.name, symbol: holding.symbol,
                           imageURL: holding.imageURL, valuation: valuation)
        }
        return Snapshot(owner: snapshot.owner, network: snapshot.network, holdings: holdings,
                        fetchedAt: snapshot.fetchedAt, pricesFetchedAt: now())
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
