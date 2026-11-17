import Foundation
import Testing
import Transactions
@testable import Privacy

struct PrivateAssetTests {
    static let tokens: [(PrivateAsset, String)] = [
        (.token(.usdc), "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
        (.token(.usdt), "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"),
        (.token(.devnetUSDC), "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"),
    ]

    @Test(arguments: tokens)
    func `Token assets carry their mints`(asset: PrivateAsset, mint: String) throws {
        let bytes = try Address(mint).bytes

        #expect(asset.mintBytes == bytes)
        #expect(PrivateAsset(mintBytes: bytes) == asset)
    }

    @Test
    func `Other mints have no asset`() {
        #expect(PrivateAsset(mintBytes: [UInt8](repeating: 7, count: 32)) == nil)
    }

    @Test(arguments: tokens.map { ($0.1, PrivateAsset?.some($0.0)) }
        + [("So11111111111111111111111111111111111111112", nil)])
    func `Tokens map to the private asset that holds them`(mint: String, privateAsset: PrivateAsset?) throws {
        #expect(PrivateAsset(.token(mint: try Address(mint))) == privateAsset)
    }

    @Test
    func `Native SOL maps to the private SOL asset`() {
        #expect(PrivateAsset(.nativeSOL) == .nativeSOL)
    }

    @Test(arguments: PrivateAsset.allCases)
    func `Each private asset's asset maps back to it`(privateAsset: PrivateAsset) {
        #expect(PrivateAsset(privateAsset.asset) == privateAsset)
    }

    @Test(arguments: [
        (PrivateAsset.nativeSOL, "1"),
        (.token(.usdc), "3"),
        (.token(.usdt), "19"),
        (.token(.devnetUSDC), "59"),
    ])
    func `Each private asset is saved as its pool ID`(asset: PrivateAsset, saved: String) throws {
        #expect(String(decoding: try JSONEncoder().encode(asset), as: UTF8.self) == saved)
        #expect(try JSONDecoder().decode(PrivateAsset.self, from: Data(saved.utf8)) == asset)
    }

    @Test
    func `A pool ID that private balances don't hold can't be read`() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PrivateAsset.self, from: Data("2".utf8)) }
    }
}
