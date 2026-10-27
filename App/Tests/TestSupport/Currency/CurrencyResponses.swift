import Foundation
@testable import RPC
import Testing
@testable import widgets

/// Answers price and exchange-rate lookups through the real adapters: SOL at $150 rising 1.29%, USDC at $1, and one
/// euro for $1.25 or 150 yen.
enum CurrencyResponses {
    /// The price lookup's path.
    static let pricePath = "/price/v3"
    /// The European Central Bank's reference file path.
    static let referencePath = "/stats/eurofxref/eurofxref-daily.xml"
    /// Coinbase's exchange-rate path.
    static let coinbasePath = "/v2/exchange-rates"

    /// Answers one adapter's request by its path.
    /// - Parameter request: The adapter's request.
    /// - Returns: The response body.
    /// - Throws: A test prerequisite error for another path or currency.
    static func respond(to request: URLRequest) throws -> String {
        let url = try #require(request.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        switch url.path() {
        case pricePath:
            // Jupiter answers only the requested mints.
            let quotes = ["sol": #""sol":{"usdPrice":150,"priceChange24h":1.29}"#, "usdc": #""usdc":{"usdPrice":1}"#]
            let ids = try #require(query?.first { $0.name == "ids" }?.value).split(separator: ",")
            return "{" + ids.compactMap { quotes[String($0)] }.joined(separator: ",") + "}"
        case referencePath:
            return "<Cube><Cube currency='USD' rate='1.25'/><Cube currency='JPY' rate='150'/></Cube>"
        case coinbasePath:
            // The same rates from each currency that Coinbase is asked about: 1 / 1.25 euros and 150 / 1.25 yen a dollar.
            let rates = ["EUR": #""USD":"1.25","JPY":"150""#, "USD": #""EUR":"0.8","JPY":"120""#]
            let currency = try #require(query?.first { $0.name == "currency" }?.value)
            let body = try #require(rates[currency], "Unexpected currency: \(currency)")
            return #"{"data":{"currency":"\#(currency)","rates":{\#(body)}}}"#
        default:
            return try #require(nil as String?, "Unexpected request: \(url)")
        }
    }

    /// The real rate adapters, answered by a test's fixture transport.
    /// - Parameter http: The fixture transport, which answers every lookup unless a test makes one fail.
    /// - Returns: The exchange-rate provider for each rate source.
    static func rates(_ http: HTTPResponses = .currency())
    -> [CurrencySettings.RateSource: any ExchangeRateProviding] {
        [.europeanCentralBank: EuropeanCentralBank(transport: http), .coinbase: Coinbase(transport: http)]
    }
}
