public import Foundation

/// A source of exchange rates between currencies.
public protocol ExchangeRateProviding: Sendable {
    /// Retrieves how much of each available currency one unit of a currency buys.
    ///
    /// - Parameter currency: The ISO code of the currency to convert from, such as `USD`.
    /// - Returns: Positive rates keyed by ISO currency code, or none for an unsupported currency.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    func rates(from currency: String) async throws -> [String: Decimal]
}
