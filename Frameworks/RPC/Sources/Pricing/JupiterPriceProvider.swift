public import Foundation

/// A price provider that supplies Jupiter's mainnet USD quotes.
public struct JupiterPriceProvider: PriceProviding {
    public let network: Network = .mainnet

    private let client: HTTPClient
    private let pacer: any RequestPacing

    /// Creates a mainnet price provider.
    public init() {
        self.init(transport: URLSessionTransport())
    }

    /// Creates a price provider with an injected HTTP transport.
    ///
    /// - Parameters:
    ///   - transport: The transport that performs HTTP requests.
    ///   - clock: The clock that paces requests.
    init(transport: any HTTPTransport, clock: some Clock<Duration> = ContinuousClock()) {
        // swift-format-ignore: NeverForceUnwrap
        client = HTTPClient(endpoint: URL(string: "https://api.jup.ag/price/v3")!, transport: transport,
                            redactor: SecretRedactor(secrets: []))
        pacer = RequestPacer(interval: .seconds(3), clock: clock)
    }

    public var batchSize: Int { 50 }

    @concurrent
    public func response(for mints: [String]) async throws -> Data {
        try await Self.data(for: mints, query: "ids", headers: [:], client: client, pacer: pacer)
    }

    public func quotes(from response: Data) throws -> [String: Quote] {
        try HTTPClient.decode([String: Value?].self, from: response).compactMapValues { $0?.quote }
    }

    /// A price record in Jupiter's response.
    private struct Value: Decodable {
        let pricePerUnit: Decimal?
        /// The 24-hour change in percent, where `1.29` is a 1.29% rise.
        let percentChange: Decimal?

        /// The field names in a price record.
        private enum CodingKeys: String, CodingKey {
            case pricePerUnit = "usdPrice"
            case percentChange = "priceChange24h"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pricePerUnit = try container.decodeIfPresent(Decimal.self, forKey: .pricePerUnit)
            percentChange = try? container.decodeIfPresent(Decimal.self, forKey: .percentChange)
        }

        /// The record's quote, or `nil` without a price.
        var quote: Quote? {
            pricePerUnit.map { Quote(pricePerUnit: $0, currency: "USD", dayChange: percentChange.map { $0 / 100 }) }
        }
    }
}
