public import Foundation

/// An exchange-rate provider backed by Coinbase's public rates.
public struct CoinbaseExchangeRateProvider: ExchangeRateProviding {
    private let client: HTTPClient

    /// Creates a rate provider.
    public init() {
        self.init(transport: URLSessionTransport())
    }

    /// Creates a rate provider with an injected HTTP transport.
    ///
    /// - Parameter transport: The transport that performs HTTP requests.
    init(transport: any HTTPTransport) {
        // swift-format-ignore: NeverForceUnwrap
        client = HTTPClient(endpoint: URL(string: "https://api.coinbase.com/v2/exchange-rates")!, transport: transport,
                            redactor: SecretRedactor(secrets: []))
    }

    @concurrent
    public func rates(from currency: String) async throws -> [String: Decimal] {
        try Task.checkCancellation()
        let codes = Set(Locale.commonISOCurrencyCodes)
        guard codes.contains(currency) else { return [:] }
        let data = try await client.get(query: [URLQueryItem(name: "currency", value: currency)],
                                        headers: ["Accept": "application/json"],
                                        maximumLength: maximumPricingResponseLength)
        let response = try HTTPClient.decode(Response.self, from: data)
        guard response.data.currency == currency else { throw RPCError.decoding }
        var rates = [currency: Decimal(1)]
        for (code, text) in response.data.rates where codes.contains(code) && code != currency {
            guard let rate = Decimal(exchangeRate: text) else { throw RPCError.decoding }
            rates[code] = rate
        }
        try Task.checkCancellation()
        return rates
    }

    /// The exchange-rate response body.
    private struct Response: Decodable {
        let data: Rates

        /// The rates from one currency, each as decimal text.
        struct Rates: Decodable {
            let currency: String
            let rates: [String: String]
        }
    }
}
