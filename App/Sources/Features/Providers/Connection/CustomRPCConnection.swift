import Foundation
import RPC

/// Checks a custom RPC URL, then adds it to the providers that every window can use and chooses it.
nonisolated struct CustomRPCConnection: ProviderConnecting {
    typealias EntryError = CustomRPCError

    private let providers: ProviderStore
    private let client: @Sendable (ProviderClient.Endpoint, Network) -> ProviderClient.Client?

    /// Creates a check that adds accepted RPCs to the shared provider settings.
    /// - Parameters:
    ///   - providers: The provider settings that every window shares, which list the custom RPCs and save and choose
    ///     an accepted one.
    ///   - client: Creates the client for a candidate URL on mainnet, the network that custom RPCs serve.
    init(providers: ProviderStore,
         client: @escaping @Sendable (ProviderClient.Endpoint, Network) -> ProviderClient.Client?
             = ProviderClient.client(for:on:)) {
        self.providers = providers
        self.client = client
    }

    /// Makes one standard request and the live-updates subscriptions that portfolios and payment watches need at
    /// the URL, then adds the RPC and chooses it.
    ///
    /// They reach only a public account and a signature that no transaction carries, never a person's wallet or
    /// payment.
    /// - Parameter entry: The URL, without surrounding whitespace.
    /// - Throws: ``CustomRPCError`` or `CancellationError`, never containing the URL.
    func connect(_ entry: String) async throws {
        guard let url = URL(string: entry), let rpc = client(.custom(url), .mainnet) else { throw CustomRPCError.notHTTPS }
        let listed: [URL]
        do {
            listed = try await providers.loadedSettings().customRPCs
        } catch {
            try Task.checkCancellation()
            throw CustomRPCError.unavailable
        }
        guard !listed.contains(url) else { throw CustomRPCError.duplicate }
        let request = try GetMultipleAccounts(addresses: [Self.checkedAccount])
        do {
            _ = try await rpc.send(request)
        } catch {
            try Task.checkCancellation()
            throw (error as? RPCError)?.isRateLimited == true ? CustomRPCError.rateLimited : .unreachable
        }
        do {
            // Both subscribe at once. Each call returns once its subscriptions are acknowledged, and discarding its
            // stream closes its connection; a failure cancels the other call.
            async let accounts = rpc.changedSlots(for: [Self.checkedAccount])
            async let watch = rpc.events(for: Self.checkedSignature)
            _ = try await (accounts, watch)
        } catch {
            try Task.checkCancellation()
            throw (error as? RPCError)?.isRateLimited == true ? CustomRPCError.rateLimited : .noLiveUpdates
        }
        try Task.checkCancellation()
        do {
            try await providers.add(url)
        } catch {
            try Task.checkCancellation()
            throw CustomRPCError.storageFailed
        }
    }

    /// A well-formed signature that no transaction carries: sixty-four zero bytes, so the check watches no one's
    /// payment.
    private static var checkedSignature: String { String(repeating: "1", count: 64) }
}
