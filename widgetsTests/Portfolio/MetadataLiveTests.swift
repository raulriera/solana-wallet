import Foundation
import RPC
import Testing

/// Verifies metadata through public RPC contracts with real provider responses.
struct MetadataLiveTests {
    /// Checks Wrapped SOL on both networks and rich NFT metadata without funding or transactions.
    /// - Throws: An RPC or test prerequisite error.
    @Test("live DAS preserves SOL identity and rich asset metadata", .timeLimit(.minutes(1)))
    func retrievesLiveMetadata() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["HELIUS_API_KEY"])
        let nativeMint = "So11111111111111111111111111111111111111112"
        for network in [Network.devnet, .mainnet] {
            let rpc: any RPC = HeliusRPC(apiKey: key, network: network)
            let asset = try await rpc.send(GetAsset(id: nativeMint))
            #expect(asset.id == nativeMint)
            #expect(asset.name == "Wrapped SOL")
            #expect(asset.symbol == "SOL")
            #expect(asset.imageURL != nil)
            #expect(asset.metadata?.media?.isEmpty == false)
            #expect(asset.metadata?.kind == "FungibleToken")
            try printMetadata(asset, network: network)
        }
        let rpc: any RPC = HeliusRPC(apiKey: key, network: .mainnet)
        let collectible = try await rpc.send(GetAsset(id: "F9Lw3ki3hJ7PF9HQXsBzoY8GyE6sPoEZZdXJBsTTD2rk"))
        #expect(collectible.metadata?.description != nil)
        #expect(collectible.metadata?.websiteURL != nil)
        #expect(collectible.metadata?.metadataURL != nil)
        #expect(collectible.metadata?.attributes?.isEmpty == false)
        #expect(collectible.metadata?.collections?.first?.name != nil)
        #expect(collectible.metadata?.creators?.isEmpty == false)
        #expect(collectible.state?.royalties != nil)
        try printMetadata(collectible, network: .mainnet)
    }

    /// Prints only normalized public metadata for inspection.
    /// - Parameters:
    ///   - asset: The decoded provider response.
    ///   - network: The network queried.
    /// - Throws: An encoding error if metadata can't be represented.
    private func printMetadata(_ asset: Asset, network: Network) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print("Live metadata for \(asset.id) on \(network):\n\(String(decoding: try encoder.encode(asset.metadata), as: UTF8.self))")
    }
}
