import Foundation
@testable import RPC
import Testing
@testable import widgets

enum CurrencyResponses {
    static let pricePath = "/price/v3"
    static let referencePath = "/stats/eurofxref/eurofxref-daily.xml"
    static let coinbasePath = "/v2/exchange-rates"

    static func respond(to request: URLRequest) throws -> String {
        let url = try #require(request.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        switch url.path() {
        case pricePath:
            let quotes = ["sol": #""sol":{"usdPrice":150,"priceChange24h":1.29}"#, "usdc": #""usdc":{"usdPrice":1}"#]
            let ids = try #require(query?.first { $0.name == "ids" }?.value).split(separator: ",")
            return "{" + ids.compactMap { quotes[String($0)] }.joined(separator: ",") + "}"
        case referencePath:
            return "<Cube><Cube currency='USD' rate='1.25'/><Cube currency='JPY' rate='150'/></Cube>"
        case coinbasePath:
            let rates = ["EUR": #""USD":"1.25","JPY":"150""#, "USD": #""EUR":"0.8","JPY":"120""#]
            let currency = try #require(query?.first { $0.name == "currency" }?.value)
            let body = try #require(rates[currency], "Unexpected currency: \(currency)")
            return #"{"data":{"currency":"\#(currency)","rates":{\#(body)}}}"#
        default:
            return try #require(nil as String?, "Unexpected request: \(url)")
        }
    }

    static func rates(_ http: HTTPResponses = .currency())
    -> [CurrencySettings.RateSource: any ExchangeRateProviding] {
        [.europeanCentralBank: EuropeanCentralBank(transport: http), .coinbase: Coinbase(transport: http)]
    }
}
