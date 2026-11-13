import Foundation
import Testing
@testable import RPC

enum LiveClients {
    static func client(helius: Bool = true, network: Network = .mainnet,
                       transport: any HTTPTransport = URLSessionTransport()) throws
        -> any RPC & AccountChangeProviding & SignatureEventProviding {
        guard helius else { return SolanaRPC(network: network, transport: transport) }
        return HeliusRPC(apiKey: try heliusAPIKey(), network: network, transport: transport)
    }

    static func rings(network: Network = .devnet,
                      transport: any HTTPTransport = URLSessionTransport()) throws -> Zolana {
        HeliusRPC(apiKey: try heliusAPIKey(), network: network, transport: transport).rings
    }

    static func heliusAPIKey() throws -> String {
        let apiKey = try #require(ProcessInfo.processInfo.environment["HELIUS_API_KEY"],
                                  "HELIUS_API_KEY must be configured for live Helius tests")
        try #require(!apiKey.isEmpty && !apiKey.hasPrefix("$("),
                     "HELIUS_API_KEY must be configured for live Helius tests")
        return apiKey
    }
}
