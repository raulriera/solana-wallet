import Foundation
import Testing
import Transactions

struct AssetTests {
    @Test
    func `SOL has a decimal place for each power of ten in the billion lamports of one SOL`() {
        #expect(pow(Decimal(10), Int(Asset.nativeSOL.decimals)) == 1_000_000_000)
    }

    @Test
    func `Tokens have their mint's decimals`() throws {
        let mint = Mint(address: try Address(TokenFixtures.mint), program: .token, decimals: 2, metadata: nil)

        #expect(Asset.token(mint).decimals == 2)
    }
}
