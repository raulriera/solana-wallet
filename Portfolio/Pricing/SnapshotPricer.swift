import Foundation
import RPC

/// Revalues holdings without fetching balances or descriptive metadata.
struct SnapshotPricer: Sendable {
    let provider: any PriceProviding
    private let now: @Sendable () -> Date

    /// Creates a repricer with an independent lookup timestamp.
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

    /// Replaces all valuations with independent quotes while preserving the holdings' retrieval time.
    /// - Parameter snapshot: The complete holdings to revalue.
    /// - Returns: The same holdings with new valuations; omitted quotes remain unknown.
    /// - Throws: A network mismatch, invalid quote, provider, or cancellation error.
    @concurrent
    func snapshot(pricing snapshot: Snapshot) async throws -> Snapshot {
        try Task.checkCancellation()
        try validate(network: snapshot.network)
        var seen: Set<String> = []
        let mints = snapshot.holdings.map { mint(for: $0.id) }.filter { seen.insert($0).inserted }
        let quotes = mints.isEmpty ? [:] : try await provider.prices(for: mints)
        try Task.checkCancellation()
        let holdings = try snapshot.holdings.map { holding in
            let valuation: Valuation?
            if let quote = quotes[mint(for: holding.id)] {
                guard !quote.pricePerUnit.isNaN, quote.pricePerUnit >= 0,
                      !quote.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      quote.fetchedAt.timeIntervalSinceReferenceDate.isFinite else { throw PriceError.invalidQuote }
                valuation = Valuation(pricePerUnit: quote.pricePerUnit,
                                      total: holding.amount.flatMap { total(for: $0, price: quote.pricePerUnit) },
                                      currency: quote.currency, fetchedAt: quote.fetchedAt)
            } else {
                valuation = nil
            }
            return Holding(id: holding.id, amount: holding.amount, name: holding.name, symbol: holding.symbol,
                           imageURL: holding.imageURL, valuation: valuation, metadata: holding.metadata)
        }
        return Snapshot(owner: snapshot.owner, network: snapshot.network, holdings: holdings,
                        fetchedAt: snapshot.fetchedAt, lastIndexedSlot: snapshot.lastIndexedSlot,
                        pricesFetchedAt: now())
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
