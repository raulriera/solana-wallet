public import Foundation

/// A replaceable source of exchange rates between currencies, independent of token prices.
public protocol ExchangeRateProviding: Sendable {
    /// Retrieves how much of each available currency one unit of a currency buys.
    ///
    /// Providers own requests and response transformation; consumers receive only rates keyed by ISO currency
    /// code, including the requested currency at 1. Missing entries mean no rate is available, never a zero rate,
    /// and a currency the provider doesn't serve returns no rates. Each call makes one attempt without retrying.
    ///
    /// - Parameter currency: The ISO code of the currency to convert from, such as `USD`.
    /// - Returns: Positive rates keyed by ISO currency code, such as `EUR: 0.89` for one US dollar.
    /// - Throws: A request, transport, response, or cancellation error.
    func rates(from currency: String) async throws -> [String: Decimal]
}
