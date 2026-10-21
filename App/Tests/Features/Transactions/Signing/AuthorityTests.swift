import Testing
import Transactions
import Wallet
@testable import widgets

/// Verifies each authority reports the signature slot it fills.
struct AuthorityTests {
    /// Verifies saved and one-time authorities use their accounts' addresses.
    @Test
    func `An authority's address is its account's address`() throws {
        let fixture = try SigningFixture()

        #expect(try Authority.account(fixture.account).address == fixture.account.address)
        #expect(try Authority.oneTime(fixture.oneTime).address.value == fixture.oneTime.address)
    }
}
