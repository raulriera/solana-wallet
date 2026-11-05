import Foundation
import RPC

/// Checks a custom price server URL, then adds and chooses it.
nonisolated struct CustomPriceConnection: ProviderConnecting {
    typealias EntryError = CustomPriceError

    private let providers: ProviderStore
    private let server: @Sendable (URL) -> (any PriceProviding)?

    /// Creates a connection that adds accepted price servers to the provider settings.
    ///
    /// - Parameters:
    ///   - providers: The provider settings that list, save, and choose custom price servers.
    ///   - server: A function that creates the provider for a candidate URL.
    init(providers: ProviderStore,
         server: @escaping @Sendable (URL) -> (any PriceProviding)? = SelectedPriceProvider.server(at:)) {
        self.providers = providers
        self.server = server
    }

    func connect(_ entry: String) async throws {
        guard let url = URL(string: entry), let prices = server(url) else { throw CustomPriceError.notHTTPS }
        let listed: [URL]
        do {
            listed = try await providers.loadedPriceSettings().customServers
        } catch {
            try Task.checkCancellation()
            throw CustomPriceError.unavailable
        }
        guard !listed.contains(url) else { throw CustomPriceError.duplicate }
        let quotes: [String: Quote]
        do {
            quotes = try await prices.prices(for: [Self.checkedAccount])
        } catch {
            try Task.checkCancellation()
            throw (error as? RPCError)?.isRateLimited == true ? CustomPriceError.rateLimited : .unreachable
        }
        guard quotes[Self.checkedAccount] != nil else { throw CustomPriceError.unreachable }
        try Task.checkCancellation()
        do {
            try await providers.add(priceServer: url)
        } catch {
            try Task.checkCancellation()
            throw CustomPriceError.storageFailed
        }
    }
}
