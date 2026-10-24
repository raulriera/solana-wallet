import Foundation
import RPC
import Testing

/// Verifies live exchange rates through the public provider-neutral contract.
@Suite(.tags(.network))
struct ExchangeRateLiveTests {
    /// An exchange-rate provider, named so test results read clearly.
    enum Source: String, CaseIterable, CustomTestStringConvertible {
        case europeanCentralBank
        case coinbase

        var testDescription: String { rawValue }

        /// The provider, with a real URL session.
        var provider: any ExchangeRateProviding {
            switch self {
            case .europeanCentralBank: EuropeanCentralBank()
            case .coinbase: Coinbase()
            }
        }
    }

    /// Reads the rates from the US dollar, which both providers serve, with the euro and the yen among them.
    /// - Parameter source: The exchange-rate provider.
    @Test(.timeLimit(.minutes(1)), arguments: Source.allCases)
    func `Live providers return rates from the dollar`(source: Source) async throws {
        let rates = try await source.provider.rates(from: "USD")

        #expect(rates["USD"] == 1)
        #expect(try #require(rates["EUR"]) > 0)
        #expect(try #require(rates["JPY"]) > 0)
    }
}
