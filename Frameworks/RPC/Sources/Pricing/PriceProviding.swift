import Foundation

/// A source of market prices for token mints.
///
/// A provider fetches one batch of mints with ``response(for:)`` and transforms that response with
/// ``quotes(from:)``. Use ``prices(for:)`` to look up quotes in batches of ``batchSize``.
public protocol PriceProviding: Sendable {
    /// The provider's answer for one batch of mints, before it becomes quotes.
    associatedtype Response: Sendable

    /// The network whose mints the provider quotes.
    var network: Network { get }

    /// The most mints that one response covers.
    var batchSize: Int { get }

    /// Retrieves the provider's answer for one batch of mints.
    ///
    /// - Parameter mints: Unique mint addresses on the provider's network, at most ``batchSize`` of them.
    /// - Returns: The provider's answer.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    func response(for mints: [String]) async throws -> Response

    /// Transforms one of the provider's answers into quotes.
    ///
    /// - Parameter response: The provider's answer for one batch.
    /// - Returns: Available quotes keyed by mint address.
    /// - Throws: ``RPCError/decoding`` for an invalid answer.
    func quotes(from response: Response) throws -> [String: Quote]
}

extension PriceProviding {
    public var batchSize: Int { .max }

    /// Retrieves available unit prices for token mints.
    ///
    /// - Parameter mints: Mint addresses on the provider's network.
    /// - Returns: Available quotes keyed by mint address.
    /// - Throws: ``RPCError/decoding`` for an invalid quote or a quote of a mint that wasn't requested, another
    ///   ``RPCError``, or `CancellationError`. A failed batch fails the whole lookup.
    @concurrent
    public func prices(for mints: [String]) async throws -> [String: Quote] {
        try Task.checkCancellation()
        var result: [String: Quote] = [:]
        for batch in mints.uniqued().batches(of: batchSize) {
            try Task.checkCancellation()
            let quotes = try await quotes(from: response(for: batch))
            let requested = Set(batch)
            guard quotes.allSatisfy({ requested.contains($0.key) && $0.value.isValid }) else { throw RPCError.decoding }
            result.merge(quotes) { $1 }
        }
        try Task.checkCancellation()
        return result
    }

    /// Requests the prices of a batch of mints with one paced JSON GET at a client's endpoint.
    ///
    /// - Parameters:
    ///   - mints: The unique mint addresses in the batch.
    ///   - name: The query item that lists the mints, separated by commas.
    ///   - headers: Extra header fields for the request.
    ///   - client: The client for the price endpoint.
    ///   - pacer: The pacer that spaces the provider's requests.
    /// - Returns: The body of a successful response, at most one mebibyte long.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    static func data(for mints: [String], query name: String, headers: [String: String], client: HTTPClient,
                     pacer: any RequestPacing) async throws -> Data {
        var headers = headers
        headers["Accept"] = "application/json"
        try await pacer.wait()
        return try await client.get(query: [URLQueryItem(name: name, value: mints.joined(separator: ","))],
                                    headers: headers, maximumLength: maximumResponseLength)
    }
}

/// The longest price response body, in bytes, to accept.
private let maximumResponseLength = 1_048_576
