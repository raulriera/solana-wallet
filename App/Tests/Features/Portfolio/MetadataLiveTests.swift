import Foundation
import RPC
import Testing

/// Verifies metadata through public RPC contracts with real provider responses.
struct MetadataLiveTests {
    /// Checks Wrapped SOL identity without funding or transactions.
    /// - Throws: An RPC or test prerequisite error.
    @Test(.timeLimit(.minutes(1)))
    func `Live DAS preserves SOL identity`() async throws {
        let nativeMint = "So11111111111111111111111111111111111111112"
        let rpc = try LiveClients.client()
        let asset = try await rpc.send(GetAsset(id: nativeMint))
        #expect(asset.id == nativeMint)
        #expect(asset.name == "Wrapped SOL")
        #expect(asset.symbol == "SOL")
        #expect(asset.imageURL?.host() == "cdn.helius-rpc.com")
        #expect(asset.metadata?.media?.isEmpty == false)
        #expect(asset.metadata?.kind == "FungibleToken")
        try printMetadata(asset, network: .mainnet)
    }

    /// Checks rich NFT metadata without funding or transactions.
    /// - Throws: An RPC or test prerequisite error.
    @Test(.timeLimit(.minutes(1)))
    func `Live DAS preserves rich asset metadata`() async throws {
        let rpc = try LiveClients.client()
        let collectible = try await rpc.send(GetAsset(id: "F9Lw3ki3hJ7PF9HQXsBzoY8GyE6sPoEZZdXJBsTTD2rk"))
        #expect(collectible.metadata?.description != nil)
        #expect(collectible.metadata?.websiteURL != nil)
        #expect(collectible.metadata?.metadataURL != nil)
        #expect(collectible.metadata?.attributes?.isEmpty == false)
        #expect(collectible.metadata?.collections?.first?.name != nil)
        #expect(collectible.metadata?.creators?.isEmpty == false)
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
