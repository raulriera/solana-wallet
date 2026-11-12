import Testing
import Transactions
@testable import Privacy

struct PrivateTokenTests {
    @Test(arguments: PrivateToken.allCases)
    func `Tokens' mints are their assets' mints`(token: PrivateToken) throws {
        #expect(try token.mint.bytes == token.asset.mint)
    }
}
