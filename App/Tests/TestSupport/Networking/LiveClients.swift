import Foundation
@testable import RPC
import Testing

enum LiveClients {
    static func client(helius: Bool = true, network: Network = .mainnet,
                       transport: any HTTPTransport = URLSessionTransport()) throws
        -> any RPC & AccountChangeProviding & SignatureEventProviding {
        guard helius else { return Solana(network: network, transport: transport) }
        return HeliusRPC(apiKey: try heliusAPIKey(), network: network, transport: transport)
    }

    static func devnetRPCs() throws -> [any RPC & SignatureEventProviding] {
        try [client(network: .devnet), client(helius: false, network: .devnet)]
    }

    static func heliusAPIKey() throws -> String {
        let apiKey = try #require(ProcessInfo.processInfo.environment["HELIUS_API_KEY"],
                                  "HELIUS_API_KEY must be configured for live Helius tests")
        try #require(!apiKey.isEmpty && !apiKey.hasPrefix("$("),
                     "HELIUS_API_KEY must be configured for live Helius tests")
        return apiKey
    }
}
