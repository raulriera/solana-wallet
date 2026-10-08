import Foundation
import RPC

/// Sends mainnet requests through Helius with the API key currently saved on this device.
///
/// Each request and subscription reads the saved key, so a key saved in any window applies
/// to the next request. The client for the latest key is kept to reuse its connections.
nonisolated struct HeliusClient: RPC, AccountChangeProviding, LogoProviding {
    /// A key problem that only a new key can fix, never containing the key.
    enum Failure: Error, Equatable {
        /// No Helius API key is saved on this device.
        case missingKey
        /// Helius rejected the saved key.
        case invalidKey
    }

    let network = Network.mainnet
    private let keys: any ProviderKeyStoring
    private let clients: Clients

    /// Creates a client that reads its key from device storage before every request.
    /// - Parameters:
    ///   - keys: Device-only storage for the accepted key.
    ///   - client: Creates the mainnet Helius client for a saved key.
    init(keys: any ProviderKeyStoring,
         client: @escaping @Sendable (String) -> any RPC & AccountChangeProviding & LogoProviding = {
             HeliusRPC(apiKey: $0, network: .mainnet)
         }) {
        self.keys = keys
        clients = Clients(make: client)
    }

    /// Sends one request with the saved key, without retrying it.
    /// - Parameter request: The RPC method and its parameters.
    /// - Returns: The validated and decoded response.
    /// - Throws: ``Failure`` for a missing or rejected key, a storage error, any other `RPCError`,
    ///   or `CancellationError`.
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        let client = try await client()
        do {
            return try await client.send(request)
        } catch {
            throw Self.keyFailure(for: error) ?? error
        }
    }

    /// Observes confirmed changes to each account with the saved key.
    /// - Parameter addresses: The accounts to watch; a repeated address is watched once.
    /// - Returns: Increasing confirmed change slots after all subscriptions are acknowledged.
    /// - Throws: ``Failure`` for a missing or rejected key, a storage error, or another sanitized
    ///   subscription, transport, timeout, or cancellation error.
    func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        let client = try await client()
        do {
            return try await client.changedSlots(for: addresses)
        } catch {
            throw Self.keyFailure(for: error) ?? error
        }
    }

    /// Looks up Helius's copies of token logos with the saved key.
    /// - Parameter mints: Mint addresses; duplicates are ignored.
    /// - Returns: Logo URLs on Helius's CDN, keyed by mint address.
    /// - Throws: ``Failure`` for a missing or rejected key, a storage error, any other `RPCError`,
    ///   or `CancellationError`.
    func logos(for mints: [String]) async throws -> [String: URL] {
        let client = try await client()
        do {
            return try await client.logos(for: mints)
        } catch {
            throw Self.keyFailure(for: error) ?? error
        }
    }

    /// Reads the saved key and returns its client.
    /// - Returns: The client for the key saved now.
    /// - Throws: ``Failure/missingKey`` before a key is saved, or a storage or cancellation error.
    private func client() async throws -> any RPC & AccountChangeProviding & LogoProviding {
        guard let key = try await keys.key() else {
            try Task.checkCancellation()
            throw Failure.missingKey
        }
        return await clients.client(for: key)
    }

    /// Identifies Helius rejecting the key, so other providers' responses can't be mistaken for it.
    /// - Parameter error: An error from a Helius request or subscription.
    /// - Returns: ``Failure/invalidKey`` for HTTP 401 or 403, otherwise `nil`.
    private static func keyFailure(for error: any Error) -> Failure? {
        switch error {
        case RPCError.http(statusCode: 401, retryAfter: _), RPCError.http(statusCode: 403, retryAfter: _): .invalidKey
        default: nil
        }
    }

    /// Keeps the client for the most recent key and replaces it when the key changes.
    private actor Clients {
        private let make: @Sendable (String) -> any RPC & AccountChangeProviding & LogoProviding
        private var current: (key: String, client: any RPC & AccountChangeProviding & LogoProviding)?

        /// Creates an empty cache.
        /// - Parameter make: Creates the client for a key.
        init(make: @escaping @Sendable (String) -> any RPC & AccountChangeProviding & LogoProviding) {
            self.make = make
        }

        /// Returns the kept client for this key, or creates one for a new key.
        /// - Parameter key: The key read from storage for this request.
        /// - Returns: A client that sends requests with this key.
        func client(for key: String) -> any RPC & AccountChangeProviding & LogoProviding {
            if let current, current.key == key { return current.client }
            let client = make(key)
            current = (key, client)
            return client
        }
    }
}
