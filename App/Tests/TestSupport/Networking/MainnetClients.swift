import Foundation
@testable import RPC
import Testing

/// Real mainnet clients shared by independent read-only integration checks.
enum MainnetClients {
    /// Creates an ordinary RPC and subscription client without accessing wallet recovery.
    /// - Parameters:
    ///   - helius: Whether to use the configured Helius provider or public Solana.
    ///   - transport: The real HTTP transport, optionally recording responses for assertions.
    /// - Returns: A real client on mainnet, with DAS available through Helius.
    /// - Throws: A test prerequisite failure if Helius credentials are missing.
    static func client(helius: Bool = true,
                       transport: any HTTPTransport = URLSessionTransport()) throws
        -> any RPC & AccountChangeProviding & SignatureEventProviding {
        guard helius else { return Solana(network: .mainnet, transport: transport) }
        return HeliusRPC(apiKey: try heliusAPIKey(), network: .mainnet, transport: transport)
    }

    /// Reads the Helius key that ignored local configuration supplies to live tests.
    /// - Returns: The configured mainnet key.
    /// - Throws: A test prerequisite failure if the key is missing or wasn't expanded.
    static func heliusAPIKey() throws -> String {
        let apiKey = try #require(ProcessInfo.processInfo.environment["HELIUS_API_KEY"],
                                  "HELIUS_API_KEY must be configured for live Helius tests")
        try #require(!apiKey.isEmpty && !apiKey.hasPrefix("$("),
                     "HELIUS_API_KEY must be configured for live Helius tests")
        return apiKey
    }
}
