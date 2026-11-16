import Foundation
import Testing
import Transactions
@testable import Privacy

struct PrivateAssetTests {
    @Test(arguments: [
        (PrivateAsset.token(.usdc), "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
        (.token(.usdt), "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"),
        (.token(.devnetUSDC), "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"),
    ])
    func `Token assets carry their mints`(asset: PrivateAsset, mint: String) throws {
        let bytes = try Address(mint).bytes

        #expect(asset.mintBytes == bytes)
        #expect(PrivateAsset(mintBytes: bytes) == asset)
    }

    @Test
    func `Other mints have no asset`() {
        #expect(PrivateAsset(mintBytes: [UInt8](repeating: 7, count: 32)) == nil)
    }

    @Test(arguments: PrivateToken.supported)
    func `Tokens pay into and open the owner's associated token account`(token: PrivateToken) throws {
        let owner = try Address(TransferVectors.recipientSigningAddress)
        let payer = try Address(TransferVectors.senderSigningAddress)
        let asset = PrivateAsset.token(token)

        #expect(try asset.tokenAccount(of: owner) == TokenProgram.token.associatedAccount(owner: owner, mint: token.mint))
        #expect(try asset.openingTokenAccount(of: owner, paidBy: payer)
            == AssociatedTokenProgram.createIdempotent(owner: owner, mint: token.mint, program: .token, payer: payer))
    }

    @Test(arguments: [
        ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", PrivateAsset?.some(.token(.usdc))),
        ("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", .token(.usdt)),
        ("4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU", .token(.devnetUSDC)),
        ("So11111111111111111111111111111111111111112", nil),
    ])
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

    @Test
    func `SOL has no token account to open`() throws {
        let owner = try Address(TransferVectors.recipientSigningAddress)

        #expect(try PrivateAsset.nativeSOL.tokenAccount(of: owner) == nil)
        #expect(try PrivateAsset.nativeSOL.openingTokenAccount(of: owner, paidBy: Address(TransferVectors.senderSigningAddress)) == nil)
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
