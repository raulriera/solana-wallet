import Foundation
import RPC

/// Checks a custom RPC URL, then adds it to the providers that every window can use and chooses it.
nonisolated struct CustomRPCConnection: ProviderConnecting {
    typealias EntryError = CustomRPCError

    private let providers: any ProviderSelecting
    private let client: ProviderClient.ClientFactory

    /// Creates a check that adds accepted RPCs to the shared provider settings.
    /// - Parameters:
    ///   - providers: Reads the custom RPCs, and saves and chooses an accepted one.
    ///   - client: Creates the mainnet client for a candidate URL.
    init(providers: any ProviderSelecting,
         client: @escaping ProviderClient.ClientFactory = ProviderClient.mainnetClient(for:)) {
        self.providers = providers
        self.client = client
    }

    /// Makes one standard request and one live-updates subscription at the URL, then adds the RPC and chooses it.
    ///
    /// Both reach only a public account, never a person's wallet.
    /// - Parameter entry: The URL as entered; surrounding whitespace is ignored.
    /// - Throws: ``CustomRPCError`` or `CancellationError`, never containing the URL.
    func connect(_ entry: String) async throws {
        let text = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let rpc = client(.custom(url)) else { throw CustomRPCError.notHTTPS }
        let listed: [URL]
        do {
            listed = try await providers.settings().customRPCs
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
            throw Self.isRateLimited(error) ? CustomRPCError.rateLimited : .unreachable
        }
        do {
            // Discarding the stream closes its connection.
            _ = try await rpc.changedSlots(for: [Self.checkedAccount])
        } catch {
            try Task.checkCancellation()
            throw Self.isRateLimited(error) ? CustomRPCError.rateLimited : .noLiveUpdates
        }
        try Task.checkCancellation()
        do {
            try await providers.add(url)
        } catch {
            // A saved RPC is in use even when the previous provider's logos couldn't be removed, so only an unsaved
            // RPC is an error; settings that can't be read back count as unsaved.
            let saved = try? await providers.settings()
            guard saved?.selection == .custom(url) else {
                try Task.checkCancellation()
                throw CustomRPCError.storageFailed
            }
        }
    }

    /// Identifies an RPC that's limiting requests, over HTTP or in a subscription reply.
    /// - Parameter error: An error from a request or subscription.
    /// - Returns: Whether the RPC answered with status or code 429.
    private static func isRateLimited(_ error: any Error) -> Bool {
        switch error {
        case RPCError.http(statusCode: 429, retryAfter: _), RPCError.server(code: 429, message: _): true
        default: false
        }
    }
}
