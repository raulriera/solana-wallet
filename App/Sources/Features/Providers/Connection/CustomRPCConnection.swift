import Foundation
import RPC

/// Checks a custom RPC URL, then adds and chooses it.
nonisolated struct CustomRPCConnection: ProviderConnecting {
    typealias EntryError = CustomRPCError

    private let providers: ProviderStore
    private let client: @Sendable (ProviderClient.Endpoint, Network) -> ProviderClient.Client?

    /// Creates a connection that adds accepted RPCs to the provider settings.
    ///
    /// - Parameters:
    ///   - providers: The provider settings that list, save, and choose custom RPCs.
    ///   - client: A function that creates the client for a candidate URL on a network.
    init(providers: ProviderStore,
         client: @escaping @Sendable (ProviderClient.Endpoint, Network) -> ProviderClient.Client?
             = ProviderClient.client(for:on:)) {
        self.providers = providers
        self.client = client
    }

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

    /// A well-formed signature that no transaction carries.
    private static var checkedSignature: String { String(repeating: "1", count: 64) }
}
