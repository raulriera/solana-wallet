public import Foundation

/// A price provider backed by a person's own HTTPS price server for mainnet mints.
///
/// The provider sends `GET <endpoint>?mints=<mint>,<mint>` with at most fifty mints, three seconds apart. The server
/// answers with a JSON object of ``Quote`` values keyed by mint, and leaves out mints it can't price.
public struct CustomPrices: PriceProviding, CustomStringConvertible, CustomDebugStringConvertible {
    public let network: Network = .mainnet

    private let client: HTTPClient
    private let pacer: any RequestPacing

    /// Creates a price provider for a server, or `nil` unless the endpoint uses HTTPS and has a host.
    ///
    /// - Parameter endpoint: An HTTPS URL with a host.
    public init?(endpoint: URL) {
        self.init(endpoint: endpoint, transport: URLSessionTransport())
    }

    /// Creates a price provider with an injected HTTP transport, or `nil` for an invalid endpoint.
    ///
    /// - Parameters:
    ///   - endpoint: An HTTPS URL with a host.
    ///   - transport: The transport that performs HTTP requests.
    ///   - pacer: The request pacer.
    init?(endpoint: URL, transport: any HTTPTransport,
          pacer: any RequestPacing = RequestPacer(interval: .seconds(3), clock: ContinuousClock())) {
        guard let endpoint = endpoint.httpsEndpoint else { return nil }
        client = HTTPClient(endpoint: endpoint, transport: transport, redactor: SecretRedactor(urls: [endpoint]))
        self.pacer = pacer
    }

    public var description: String { "CustomPrices(mainnet)" }
    public var debugDescription: String { description }

    public var batchSize: Int { 50 }

    @concurrent
    public func response(for mints: [String]) async throws -> Data {
        try await Self.data(for: mints, query: "mints", headers: [:], client: client, pacer: pacer)
    }

    public func quotes(from response: Data) throws -> [String: Quote] {
        try HTTPClient.decode([String: Quote].self, from: response)
    }
}
