import Foundation
import RPC

/// Checks a custom RPC URL and the optional features its server serves, then adds and chooses it.
nonisolated struct CustomRPCConnection: ProviderConnecting {
    typealias EntryError = CustomRPCError

    private let rpcStore: RPCStore
    private let client: @Sendable (SelectedRPCProvider.Endpoint, Network) -> SelectedRPCProvider.Client?

    /// Creates a connection that adds accepted RPCs to the provider settings.
    ///
    /// - Parameters:
    ///   - rpcStore: The provider settings that list, save, and choose custom RPCs.
    ///   - client: A function that creates the client for a candidate URL on a network.
    init(rpcStore: RPCStore,
         client: @escaping @Sendable (SelectedRPCProvider.Endpoint, Network) -> SelectedRPCProvider.Client?
             = SelectedRPCProvider.client(for:on:)) {
        self.rpcStore = rpcStore
        self.client = client
    }

    func connect(_ entry: String) async throws {
        guard let url = URL(string: entry), let rpc = client(.custom(url, capabilities: []), .mainnet) else {
            throw CustomRPCError.notHTTPS
        }
        let isListed: Bool
        do {
            isListed = try await rpcStore.loadedSettings().customRPC(for: url) != nil
        } catch {
            try Task.checkCancellation()
            throw CustomRPCError.unavailable
        }
        guard !isListed else { throw CustomRPCError.duplicate }
        async let account = rpc.accounts(at: [Self.checkedAccount])
        async let liveUpdates: Void = Self.checkLiveUpdates(on: rpc)
        async let servesLogos = rpc.servesLogos(checking: Self.checkedAccount)
        async let servesPrivateBalances = rpc.servesPrivateBalances()
        do {
            _ = try await account
        } catch {
            throw try Self.entryError(for: error, otherwise: .unreachable)
        }
        var capabilities: Capabilities = []
        do {
            try await liveUpdates
            if try await servesLogos { capabilities.insert(.logos) }
            if try await servesPrivateBalances { capabilities.insert(.privateBalances) }
        } catch {
            throw try Self.entryError(for: error, otherwise: .noLiveUpdates)
        }
        try Task.checkCancellation()
        do {
            try await rpcStore.add(url, capabilities: capabilities)
        } catch {
            try Task.checkCancellation()
            throw CustomRPCError.storageFailed
        }
    }

    /// Opens the account and signature subscriptions that every RPC must serve, then closes them.
    ///
    /// - Parameter rpc: The RPC to check.
    /// - Throws: The subscriptions' error, or `CancellationError`.
    private static func checkLiveUpdates(on rpc: SelectedRPCProvider.Client) async throws {
        async let changes = rpc.changedSlots(for: [checkedAccount])
        async let watch = rpc.events(for: checkedSignature)
        _ = try await (changes, watch)
    }

    /// Returns the error that a failed check shows.
    ///
    /// - Parameters:
    ///   - error: The check's error.
    ///   - fallback: The error to show unless the RPC is rate-limited.
    /// - Returns: ``CustomRPCError/rateLimited`` for a rate limit, or the fallback.
    /// - Throws: `CancellationError` when the check was cancelled.
    private static func entryError(for error: any Error, otherwise fallback: CustomRPCError) throws -> CustomRPCError {
        try Task.checkCancellation()
        return (error as? RPCError)?.isRateLimited == true ? .rateLimited : fallback
    }

    /// A well-formed signature that no transaction carries.
    private static var checkedSignature: String { String(repeating: "1", count: 64) }
}
