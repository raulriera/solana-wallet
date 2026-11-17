import Foundation
import Testing
import Transactions

struct MintTests {
    @Test
    func `A saved mint keeps its facts and not its account data`() throws {
        let pyusd = try MetadataFixtures.mint(MetadataFixtures.pyusdMint, program: .token2022,
                                              data: MetadataFixtures.pyusdMintData)

        let saved = try JSONDecoder().decode(Mint.self, from: JSONEncoder().encode(pyusd))

        #expect(saved == Mint(address: pyusd.address, program: .token2022, decimals: pyusd.decimals,
                              metadata: TokenMetadata(name: "PayPal USD", symbol: "PYUSD")))
        #expect(saved.hashValue == pyusd.hashValue)
        #expect(Set([Asset.token(saved), .token(pyusd)]).count == 1)
        #expect(throws: TokenError.invalidAccount) { try saved.associatedAccountSize }
        #expect(throws: TokenError.invalidAccount) { try saved.isNonFungible }
    }
}
