import Foundation
import RPC

/// Looks up mainnet prices through the selected price provider, or supplies none when prices are off.
nonisolated struct SelectedPriceProvider: PriceProviding {
    let network: Network = .mainnet

    private let providers: ProviderStore
    private let jupiter: any PriceProviding
    private let servers: ClientCache<URL, any PriceProviding>

    /// Creates a price provider that reads the price provider choice before every lookup.
    ///
    /// - Parameters:
    ///   - providers: The provider settings to read.
    ///   - jupiter: The provider for Jupiter's prices.
    ///   - server: A function that creates the provider for a custom price server.
    init(providers: ProviderStore, jupiter: any PriceProviding = Jupiter(),
         server: @escaping @Sendable (URL) -> (any PriceProviding)? = Self.server(at:)) {
        self.providers = providers
        self.jupiter = jupiter
        servers = ClientCache(make: server)
    }

    @concurrent
    func response(for mints: [String]) async throws -> [String: Quote] {
        switch try await providers.loadedPriceSettings().selection {
        case .jupiter: try await jupiter.prices(for: mints)
        case .custom(let url): try await servers.client(for: url).prices(for: mints)
        case .off: [:]
        }
    }

    func quotes(from response: [String: Quote]) -> [String: Quote] {
        response
    }

    /// Creates the provider for a custom price server.
    ///
    /// - Parameter url: The price server URL.
    /// - Returns: The server's provider, or `nil` for a URL that isn't HTTPS with a host.
    static func server(at url: URL) -> (any PriceProviding)? {
        CustomPrices(endpoint: url)
    }
}
