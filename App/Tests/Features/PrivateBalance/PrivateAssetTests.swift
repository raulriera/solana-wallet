import Portfolio
import Privacy
import Testing
import Transactions

@testable import widgets

struct PrivateAssetTests {
    @Test(arguments: [
        (String?.none, PrivateAsset?.some(.sol)),
        ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", .token(.usdc)),
        ("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", .token(.usdt)),
        ("4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU", .token(.devnetUSDC)),
        ("So11111111111111111111111111111111111111112", nil),
    ])
    func `Mints map to the private asset that holds them`(mint: String?, asset: PrivateAsset?) throws {
        #expect(PrivateAsset(mint: try mint.map(Address.init)) == asset)
    }

    @Test(arguments: [
        (Holding.Identity.nativeSOL, PrivateAsset?.some(.sol)),
        (.asset("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"), .token(.usdc)),
        (.asset("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"), .token(.usdt)),
        (.asset("4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"), .token(.devnetUSDC)),
        (.asset("So11111111111111111111111111111111111111112"), nil),
    ])
    func `Holdings map to the private asset that holds them`(holding: Holding.Identity, asset: PrivateAsset?) {
        #expect(PrivateAsset(holding) == asset)
    }

    @Test(arguments: PrivateAsset.allCases)
    func `Each asset's holding maps back to the asset`(asset: PrivateAsset) {
        #expect(PrivateAsset(asset.holding) == asset)
    }

    @Test(arguments: [
        (PrivateAsset.sol, UInt8(9)), (.token(.usdc), 6), (.token(.usdt), 6), (.token(.devnetUSDC), 6),
    ])
    func `Assets have their mint's decimals`(asset: PrivateAsset, decimals: UInt8) {
        #expect(asset.decimals == decimals)
    }

    @Test(arguments: [(PrivateAsset.sol, UInt64(5_000)), (.token(.devnetUSDC), 0)])
    func `Only SOL moves public lamports`(asset: PrivateAsset, lamports: UInt64) {
        #expect(asset.lamports(moving: 5_000) == lamports)
    }
}
