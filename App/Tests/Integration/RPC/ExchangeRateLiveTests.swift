import Foundation
import RPC
import Testing

@Suite(.tags(.network))
struct ExchangeRateLiveTests {
    enum Source: String, CaseIterable, CustomTestStringConvertible {
        case europeanCentralBank
        case coinbase

        var testDescription: String { rawValue }

        var provider: any ExchangeRateProviding {
            switch self {
            case .europeanCentralBank: EuropeanCentralBankExchangeRateProvider()
            case .coinbase: CoinbaseExchangeRateProvider()
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: Source.allCases)
    func `Live providers return rates from the dollar`(source: Source) async throws {
        let rates = try await source.provider.rates(from: "USD")

        #expect(rates["USD"] == 1)
        #expect(try #require(rates["EUR"]) > 0)
        #expect(try #require(rates["JPY"]) > 0)
    }
}
