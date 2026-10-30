import Foundation

/// A price provider that supplies Jupiter's mainnet USD quotes.
public struct Jupiter: PriceProviding, CustomStringConvertible, CustomDebugStringConvertible {
    public let network: Network = .mainnet

    private let apiKey: String?
    private let transport: any HTTPTransport
    private let redactor: any TextRedactor
    private let pacer: any RequestPacing

    /// Creates a mainnet price provider.
    ///
    /// - Parameter apiKey: A Jupiter API key, or `nil` for keyless access.
    public init(apiKey: String? = nil) {
        self.init(apiKey: apiKey, transport: URLSessionTransport())
    }

    /// Creates a price provider with an injected HTTP transport.
    ///
    /// - Parameters:
    ///   - apiKey: A Jupiter API key, or `nil` for keyless access.
    ///   - transport: The transport that performs HTTP requests.
    ///   - pacer: The request pacer, or `nil` for the default pace of the access type.
    init(apiKey: String? = nil, transport: any HTTPTransport, pacer: (any RequestPacing)? = nil) {
        self.apiKey = apiKey
        self.transport = transport
        redactor = SecretRedactor(secrets: apiKey.map { [$0] } ?? [])
        self.pacer = pacer ?? RequestPacer(
            interval: apiKey == nil ? .seconds(3) : .milliseconds(1_500), clock: ContinuousClock()
        )
    }

    public var description: String { "Jupiter(mainnet)" }
    public var debugDescription: String { description }

    @concurrent
    public func prices(for mints: [String]) async throws -> [String: Quote] {
        try Task.checkCancellation()
        var quotes: [String: Quote] = [:]
        for batch in mints.uniqued().batches(of: 50) {
            try Task.checkCancellation()
            let values = try await fetch(batch)
            for (mint, value) in values {
                guard batch.contains(mint) else { throw RPCError.decoding }
                if let quote = try value?.makeQuote() { quotes[mint] = quote }
            }
        }
        try Task.checkCancellation()
        return quotes
    }

    /// Sends one price request for a batch of mints.
    ///
    /// - Parameter mints: The unique mint addresses in the batch.
    /// - Returns: The price records keyed by mint address.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    private func fetch(_ mints: [String]) async throws -> [String: Value?] {
        // swift-format-ignore: NeverForceUnwrap
        let url = URL(string: "https://api.jup.ag/price/v3")!
            .appending(queryItems: [URLQueryItem(name: "ids", value: mints.joined(separator: ","))])
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        try await pacer.wait()
        let data = try await transport.responseData(for: request, redactor: redactor)
        do {
            return try JSONDecoder().decode([String: Value?].self, from: data)
        } catch {
            try Task.checkCancellation()
            throw RPCError.decoding
        }
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

        /// Validates the decoded price and converts it to a quote.
        ///
        /// - Returns: A quote, or `nil` without a price.
        /// - Throws: ``RPCError/decoding`` for a negative or invalid price.
        func makeQuote() throws -> Quote? {
            guard let pricePerUnit else { return nil }
            guard !pricePerUnit.isNaN, pricePerUnit >= 0 else { throw RPCError.decoding }
            return Quote(pricePerUnit: pricePerUnit, currency: "USD", dayChange: percentChange.map { $0 / 100 })
        }
    }
}
