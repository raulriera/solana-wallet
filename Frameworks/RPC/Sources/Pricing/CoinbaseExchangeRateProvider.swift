public import Foundation

/// An exchange-rate provider backed by Coinbase's public rates.
public struct CoinbaseExchangeRateProvider: ExchangeRateProviding {
    private let transport: any HTTPTransport

    /// Creates a rate provider.
    public init() {
        self.init(transport: URLSessionTransport())
    }

    /// Creates a rate provider with an injected HTTP transport.
    ///
    /// - Parameter transport: The transport that performs HTTP requests.
    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    @concurrent
    public func rates(from currency: String) async throws -> [String: Decimal] {
        try Task.checkCancellation()
        let codes = Set(Locale.commonISOCurrencyCodes)
        guard codes.contains(currency) else { return [:] }
        // swift-format-ignore: NeverForceUnwrap
        let url = URL(string: "https://api.coinbase.com/v2/exchange-rates")!
            .appending(queryItems: [URLQueryItem(name: "currency", value: currency)])
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await transport.responseData(for: request, redactor: SecretRedactor(secrets: []))
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            try Task.checkCancellation()
            throw RPCError.decoding
        }
        guard response.data.currency == currency else { throw RPCError.decoding }
        var rates = [currency: Decimal(1)]
        for (code, text) in response.data.rates where codes.contains(code) && code != currency {
            guard let rate = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
                  !rate.isNaN, rate > 0 else { throw RPCError.decoding }
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
