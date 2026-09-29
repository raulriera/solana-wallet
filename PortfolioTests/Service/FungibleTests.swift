import Foundation
import RPC
import Testing
@testable import Portfolio

/// Verifies the fungible-only scope for refreshed and previously persisted portfolios.
struct FungibleTests {
    /// Verifies an excluded page cannot add holdings, affect valuation, or hide later fungibles.
    /// - Parameter kind: An NFT or unrecognized DAS interface returned despite the request filter.
    /// - Throws: A refresh, storage, or test prerequisite error.
    @Test("portfolio excludes nonfungibles and continues to later fungible pages", arguments: [
        "V1_NFT", "ProgrammableNFT", "MplCoreAsset", "MplCoreCollection", "MplBubblegumV2", "Custom", "FutureKind",
    ])
    func excludesNonfungibles(kind: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        let http = AssetResponses { request in
            let items: String
            switch request.page {
            case 1:
                items = #"""
                [{"id":"excluded","interface":"\#(kind)","compression":{"compressed":true},
                  "token_info":{"balance":1,"decimals":0,
                    "price_info":{"price_per_token":1000,"total_price":1000,"currency":"USD"}}}]
                """#
            case 2:
                items = #"""
                [{"id":"token","interface":"FungibleToken","token_info":{"balance":1,"decimals":0}},
                 {"id":"asset","interface":"FungibleAsset","token_info":{"balance":3,"decimals":6}}]
                """#
            default:
                items = "[]"
            }
            return Data(#"{"page":\#(request.page),"limit":2,"items":\#(items),"nativeBalance":{"lamports":9}}"#.utf8)
        }
        let service = Portfolio(rpc: http.client, store: store, pageSize: 2)
        var updates = await service.updates(for: "wallet").makeAsyncIterator()
        _ = try #require(await updates.next())
        let update = try #require(await updates.next())
        if let error = update.error { throw error }
        let result = try #require(update.snapshot)

        #expect(result.holdings.map(\.id) == [.nativeSOL, .asset("token"), .asset("asset")])
        #expect(result.holdings.map(\.amount) == [
            Amount(units: 9, decimals: 9), Amount(units: 1, decimals: 0), Amount(units: 3, decimals: 6),
        ])
        #expect(result.knownValuesByCurrency.isEmpty)
        #expect(result.unpricedHoldingCount == 3)
        #expect(await http.requests.map(\.page) == [1, 2, 3])
        #expect(store.snapshot(for: CacheKey(owner: "wallet", network: .mainnet)) == result)
        #expect(await updates.next() == nil)
    }

    /// Verifies an older mixed-asset cache is absent during refresh and after a network failure.
    /// - Throws: A cache fixture or test prerequisite error.
    @Test("legacy mixed portfolios cannot restore NFTs while offline")
    func ignoresMixedAssetCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        let key = CacheKey(owner: "wallet", network: .mainnet)
        let mixed = Snapshot(owner: "wallet", network: .mainnet, holdings: [
            Holding(id: .asset("nft"), amount: Amount(units: 1, decimals: 0), name: "NFT", symbol: nil,
                    imageURL: nil, valuation: nil, metadata: Metadata(kind: "V1_NFT")),
        ], fetchedAt: .distantPast, lastIndexedSlot: nil)
        try store.save(mixed, for: key)
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        envelope["version"] = 1
        try JSONSerialization.data(withJSONObject: envelope).write(to: file)
        let http = AssetResponses { _ in throw URLError(.notConnectedToInternet) }
        let service = Portfolio(rpc: http.client, store: store)
        var updates = await service.updates(for: "wallet").makeAsyncIterator()

        let initial = try #require(await updates.next())
        #expect(initial.snapshot == nil)
        #expect(initial.isRefreshing)
        let failed = try #require(await updates.next())
        #expect(failed.snapshot == nil)
        #expect(failed.error != nil)
        #expect(store.snapshot(for: key) == nil)
        #expect(await updates.next() == nil)
    }
}
