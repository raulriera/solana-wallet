public import Foundation

/// Coinbase's public exchange rates, through the shared exchange-rate contract.
///
/// Coinbase serves about 150 currencies, updated through the day, without a key. Its responses also carry crypto
/// assets; only ISO currencies reach consumers.
public struct Coinbase: ExchangeRateProviding {
    private let transport: any HTTPTransport

    /// Creates a rate provider with an ephemeral URL session.
    public init() {
        self.init(transport: URLSessionTransport())
    }

    /// Creates a rate provider with an injected HTTP transport.
    /// - Parameter transport: The transport performing real requests or supplying HTTP test fixtures.
    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    /// Reads the current rates from the requested currency.
    /// - Parameter currency: The ISO code of the currency to convert from.
    /// - Returns: Rates keyed by ISO currency code, or none when Coinbase doesn't serve the currency.
    /// - Throws: An HTTP, transport, decoding, or cancellation error.
    @concurrent
    public func rates(from currency: String) async throws -> [String: Decimal] {
        try Task.checkCancellation()
        let codes = Set(Locale.commonISOCurrencyCodes)
        guard codes.contains(currency) else { return [:] }
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

    /// The adapter's private DTO; consumers see only rates keyed by ISO code.
    private struct Response: Decodable {
        let data: Rates

        /// The rates from one currency, each as decimal text.
        struct Rates: Decodable {
            let currency: String
            let rates: [String: String]
        }
    }
}
