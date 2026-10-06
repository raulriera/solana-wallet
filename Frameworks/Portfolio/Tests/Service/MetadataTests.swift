import Foundation
import RPC
import Testing
@testable import Portfolio

/// Verifies metadata survives portfolio mapping and persistence without changing SOL identities.
struct MetadataTests {
    /// Verifies every metadata group is cached, and owned Wrapped SOL supplies the native image without another request.
    @Test
    func `Portfolio preserves rich Wrapped SOL metadata and keeps native SOL separate`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        let http = AssetResponses { request in
            Data(#"{"page":\#(request.page),"limit":1000,"items":\#(request.page == 1 ? "[" + wrappedAsset + "]" : "[]"),"nativeBalance":{"lamports":42}}"#.utf8)
        }
        let service = Portfolio(rpc: http.client, store: store)
        let result = try await refreshedSnapshot(service)
        let native = try #require(result.holdings.first { $0.id == .nativeSOL })
        let wrapped = try #require(result.holdings.first { $0.id == .asset(nativeMint) })
        let decoded = try JSONDecoder().decode(Asset.self, from: Data(wrappedAsset.utf8))
        #expect(native.name == "Solana")
        #expect(native.symbol == "SOL")
        #expect(native.amount == Amount(units: 42, decimals: 9))
        #expect(native.imageURL == wrapped.imageURL)
        #expect(wrapped.imageURL?.absoluteString == "https://cdn.example.com/provider-sol.png")
        #expect(native.metadata == nil)
        #expect(wrapped.name == "Provider Wrapped SOL")
        #expect(wrapped.symbol == "WSOL")
        #expect(wrapped.amount == Amount(units: 123, decimals: 9))
        #expect(wrapped.metadata == decoded.metadata)
        #expect(await http.assetRequests.isEmpty)
        let restored = FileSnapshotStore(directory: directory).snapshot(for: CacheKey(owner: "wallet", network: .mainnet))
        #expect(restored == result)
    }

    /// Verifies a SOL-only wallet uses one same-network native-mint lookup and leaves unknown metadata absent.
    @Test
    func `Native SOL resolves its provider image once without adding a Wrapped SOL holding`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = AssetResponses(network: .devnet) { _ in emptyPage }
        let result = try await refreshedSnapshot(Portfolio(rpc: http.client, store: FileSnapshotStore(directory: directory)))
        #expect(result.network == .devnet)
        #expect(result.holdings.map(\.id) == [.nativeSOL])
        #expect(result.holdings.first?.imageURL?.absoluteString == "https://cdn.example.com/sol.png")
        #expect(result.holdings.first?.metadata == nil)
        #expect(await http.assetRequests == [nativeMint])
        #expect(await http.requests.count == 1)
    }

    /// Verifies failed or misattributed metadata never becomes a fallback image or replaces the cache.
    /// - Parameter mismatched: Whether the provider returns the wrong asset instead of a transport failure.
    @Test(arguments: [false, true])
    func `Native image failures preserve the cached snapshot`(mismatched: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        let key = CacheKey(owner: "wallet", network: .mainnet)
        let cached = Snapshot(owner: "wallet", network: .mainnet, holdings: [], fetchedAt: .distantPast, lastIndexedSlot: nil)
        try store.save(cached, for: key)
        let http = AssetResponses(assetResponse: { _ in
            if mismatched { return Data(#"{"id":"wrong-mint","interface":"FungibleToken"}"#.utf8) }
            throw URLError(.notConnectedToInternet)
        }) { _ in emptyPage }
        var updates = await Portfolio(rpc: http.client, store: store).updates(for: "wallet").makeAsyncIterator()
        _ = try #require(await updates.next())
        let failed = try #require(await updates.next())
        #expect(failed.error != nil)
        #expect(failed.snapshot == cached)
        #expect(store.snapshot(for: key) == cached)
        #expect(await http.assetRequests.count == 1)
    }
}

/// Reads one complete refresh from a real portfolio service.
/// - Parameter service: The service backed by the real RPC adapter and HTTP fixtures.
/// - Returns: The successfully refreshed snapshot.
/// - Throws: A refresh or test prerequisite error.
private func refreshedSnapshot(_ service: Portfolio) async throws -> Snapshot {
    var updates = await service.updates(for: "wallet").makeAsyncIterator()
    _ = try #require(await updates.next())
    let update = try #require(await updates.next())
    if let error = update.error { throw error }
    return try #require(update.snapshot)
}

private let nativeMint = "So11111111111111111111111111111111111111112"
private let emptyPage = Data(#"{"page":1,"limit":1000,"items":[],"nativeBalance":{"lamports":42}}"#.utf8)
private let wrappedAsset = #"""
{"id":"So11111111111111111111111111111111111111112","interface":"FungibleToken","mutable":true,"burnt":false,
 "content":{"json_uri":"https://example.com/sol.json",
   "metadata":{"name":"Provider Wrapped SOL","symbol":"WSOL","description":"Kept intact","token_standard":"Fungible",
     "attributes":[{"trait_type":"number","value":9007199254740993}]},
   "links":{"image":"https://example.com/provider-sol.png","external_url":"https://example.com"},
   "files":[{"uri":"https://example.com/provider-sol.png","cdn_uri":"https://cdn.example.com/provider-sol.png","mime":"image/png"}]},
 "grouping":[{"group_key":"collection","group_value":"collection","collection_metadata":{"name":"Collection"}}],
 "creators":[{"address":"creator","share":100,"verified":true}],
 "token_info":{"balance":123,"decimals":9,"supply":18446744073709551615,"token_program":"program"},
 "ownership":{"owner":"wallet","frozen":false,"delegated":false}}
"""#
