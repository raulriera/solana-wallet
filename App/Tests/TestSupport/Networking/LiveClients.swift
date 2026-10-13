import Foundation
@testable import RPC
import Testing

/// Real clients shared by independent live integration checks.
enum LiveClients {
    /// Creates an ordinary RPC and subscription client without accessing wallet recovery.
    /// - Parameters:
    ///   - helius: Whether to use the configured Helius provider or public Solana.
    ///   - network: Mainnet for read-only checks; devnet for tests that fund wallets or pay fees, and for read-only checks of behavior that only devnet runs yet.
    ///   - transport: The real HTTP transport, optionally recording responses for assertions.
    /// - Returns: A real client on the network, with DAS available through Helius.
    /// - Throws: A test prerequisite failure if Helius credentials are missing.
    static func client(helius: Bool = true, network: Network = .mainnet,
                       transport: any HTTPTransport = URLSessionTransport()) throws
        -> any RPC & AccountChangeProviding & SignatureEventProviding {
        guard helius else { return Solana(network: network, transport: transport) }
        return HeliusRPC(apiKey: try heliusAPIKey(), network: network, transport: transport)
    }

    /// Reads the Helius key that ignored local configuration supplies to live tests.
    /// - Returns: The configured key, which serves mainnet and devnet.
    /// - Throws: A test prerequisite failure if the key is missing or wasn't expanded.
    static func heliusAPIKey() throws -> String {
        let apiKey = try #require(ProcessInfo.processInfo.environment["HELIUS_API_KEY"],
                                  "HELIUS_API_KEY must be configured for live Helius tests")
        try #require(!apiKey.isEmpty && !apiKey.hasPrefix("$("),
                     "HELIUS_API_KEY must be configured for live Helius tests")
        return apiKey
    }
}
