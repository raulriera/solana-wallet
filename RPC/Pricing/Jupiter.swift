import Foundation

/// A Price V3 adapter that supplies mainnet USD quotes through the shared pricing contract.
public struct Jupiter: PriceProviding, CustomStringConvertible, CustomDebugStringConvertible {
    /// Jupiter quotes mainnet assets; these prices must not be applied to devnet balances.
    public let network: Network = .mainnet

    private let apiKey: String?
    private let transport: any HTTPTransport
    private let redactor: any TextRedactor

    /// Creates a mainnet price provider with an ephemeral URL session.
    /// - Parameter apiKey: An optional Jupiter API key; `nil` uses keyless access.
    public init(apiKey: String? = nil) {
        self.init(apiKey: apiKey, transport: URLSessionTransport())
    }

    /// Creates a price provider with an injected HTTP transport.
    /// - Parameters:
    ///   - apiKey: An optional key sent only in the authentication header.
    ///   - transport: The transport performing real requests or supplying HTTP test fixtures.
    init(apiKey: String? = nil, transport: any HTTPTransport) {
        self.apiKey = apiKey
        self.transport = transport
        redactor = SecretRedactor(secrets: apiKey.map { [$0] } ?? [])
    }

    /// A textual representation that omits authentication credentials.
    public var description: String { "Jupiter(mainnet)" }
    /// A debugging representation that omits authentication credentials.
    public var debugDescription: String { description }

    /// Retrieves available prices in sequential batches of at most fifty unique mints.
    ///
    /// Batching is internal to the adapter. Each batch is attempted once; a failure
    /// prevents partial success from reaching the consumer. No holdings or metadata
    /// requests, polling, fallback, or retries are performed.
    /// - Parameter mints: Mainnet mint addresses; duplicates are ignored.
    /// - Returns: Normalized quotes for the mints whose prices are available.
    /// - Throws: An HTTP, transport, decoding, or cancellation error.
    @concurrent
    public func prices(for mints: [String]) async throws -> [String: Quote] {
        try Task.checkCancellation()
        var seen: Set<String> = []
        let unique = mints.filter { seen.insert($0).inserted }
        var quotes: [String: Quote] = [:]
        for start in stride(from: 0, to: unique.count, by: 50) {
            try Task.checkCancellation()
            let batch = Array(unique[start..<min(start + 50, unique.count)])
            let values = try await fetch(batch)
            let fetchedAt = Date()
            for (mint, value) in values {
                guard batch.contains(mint), !value.usdPrice.isNaN, value.usdPrice >= 0 else { throw RPCError.decoding }
                quotes[mint] = Quote(pricePerUnit: value.usdPrice, currency: "USD",
                                     fetchedAt: fetchedAt, blockID: value.blockId)
            }
        }
        try Task.checkCancellation()
        return quotes
    }

    /// Sends one Price V3 request and decodes its private wire representation.
    /// - Parameter mints: The unique addresses in this batch.
    /// - Returns: The provider's price records, before normalization.
    /// - Throws: An HTTP, transport, decoding, or cancellation error.
    private func fetch(_ mints: [String]) async throws -> [String: Value] {
        let url = URL(string: "https://api.jup.ag/price/v3")!
            .appending(queryItems: [URLQueryItem(name: "ids", value: mints.joined(separator: ","))])
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        let data = try await transport.responseData(for: request, redactor: redactor)
        do {
            return try JSONDecoder().decode([String: Value].self, from: data)
        } catch {
            try Task.checkCancellation()
            throw RPCError.decoding
        }
    }

    /// The adapter's private DTO; consumers see only normalized quotes.
    private struct Value: Decodable {
        let usdPrice: Decimal
        let blockId: UInt64?
    }
}
