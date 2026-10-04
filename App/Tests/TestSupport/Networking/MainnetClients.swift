import Foundation
import RPC
import Testing

/// Real mainnet clients shared by independent read-only integration checks.
enum MainnetClients {
    /// Creates an ordinary RPC and subscription client without accessing wallet recovery.
    /// - Parameter helius: Whether to use the configured Helius provider or public Solana.
    /// - Returns: A real client on mainnet, with DAS available through Helius.
    /// - Throws: A test prerequisite failure if Helius credentials are missing.
    static func client(helius: Bool = true) throws -> any RPC & AccountChangeProviding {
        guard helius else { return Solana(network: .mainnet) }
        let apiKey = try #require(ProcessInfo.processInfo.environment["HELIUS_API_KEY"],
                                  "HELIUS_API_KEY must be configured for live Helius tests")
        try #require(!apiKey.isEmpty && !apiKey.hasPrefix("$("),
                     "HELIUS_API_KEY must be configured for live Helius tests")
        return HeliusRPC(apiKey: apiKey, network: .mainnet)
    }
}
