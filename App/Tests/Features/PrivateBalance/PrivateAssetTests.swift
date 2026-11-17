import Privacy
import Testing

@testable import widgets

struct PrivateAssetTests {
    @Test(arguments: [(PrivateAsset.nativeSOL, UInt64(5_000)), (.token(.devnetUSDC), 0)])
    func `Only SOL moves public lamports`(asset: PrivateAsset, lamports: UInt64) {
        #expect(asset.lamports(moving: 5_000) == lamports)
    }
}
