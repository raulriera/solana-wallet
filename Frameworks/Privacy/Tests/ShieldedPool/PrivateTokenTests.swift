@testable import Privacy
import Testing
import Transactions

struct PrivateTokenTests {
    @Test(arguments: PrivateToken.allCases)
    func `Tokens' mints are their assets' mints`(token: PrivateToken) throws {
        #expect(try token.mint.bytes == token.asset.mint)
    }
}
