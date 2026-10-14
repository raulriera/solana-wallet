import Foundation
import RPC
import Portfolio
import Testing

/// Tests saved snapshots through the framework's public API.
struct SnapshotTests {
    /// Verifies a snapshot read without a price lookup saves no lookup time and loads unchanged.
    /// - Throws: An encoding, decoding, or test prerequisite error.
    @Test
    func `Snapshots without a price lookup time round-trip`() throws {
        let original = Snapshot(owner: "wallet", network: .mainnet, holdings: [
            Holding(id: .nativeSOL, amount: Amount(units: 100, decimals: 9), name: "Solana", symbol: "SOL",
                    imageURL: nil, valuation: Valuation(pricePerUnit: 1, total: 1, currency: "USD")),
        ], fetchedAt: Date(timeIntervalSince1970: 1_999_999_995))
        let encoded = try JSONEncoder().encode(original)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields["pricesFetchedAt"] == nil)
        let decoded = try JSONDecoder().decode(Snapshot.self, from: encoded)
        #expect(decoded == original)
        #expect(decoded.pricesFetchedAt == nil)
    }
}
