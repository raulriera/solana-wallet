import Foundation
import Testing
import Transactions

struct MintTests {
    @Test(arguments: TokenFixtures.transfers)
    func `A decoded mint equals the same mint saved and read back`(_ fixture: TokenFixture) throws {
        let decoded = try fixture.mint()

        let saved = try JSONDecoder().decode(Mint.self, from: JSONEncoder().encode(decoded))

        #expect(saved == decoded)
        #expect(saved.hashValue == decoded.hashValue)
        #expect(Set([Asset.token(saved), .token(decoded)]).count == 1)
    }

    @Test
    func `Mints with different decimals are different mints`() throws {
        let address = try Address(TokenFixtures.mint)

        #expect(Mint(address: address, program: .token, decimals: 6, metadata: nil)
            != Mint(address: address, program: .token, decimals: 9, metadata: nil))
    }
}
