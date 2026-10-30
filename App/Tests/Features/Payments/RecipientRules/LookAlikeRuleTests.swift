import Testing
import Transactions
@testable import widgets

struct LookAlikeRuleTests {
    private static let original = try! Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
    private static let lookAlike = try! Address("6d8tEyrqPq1bEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
    private static let unrelated = try! Address("F3sVqBYJWSBdbsMtZes3AEKkBaiHHokhENFWA1PoMFSf")

    @Test func `An address that only differs in the middle is a look-alike`() {
        let context = RecipientContext(knownAddresses: [Self.original], paidAddresses: [])
        #expect(LookAlikeRule().warning(for: Self.lookAlike, in: context) == .lookAlike)
    }

    @Test func `A known address isn't a look-alike`() {
        let context = RecipientContext(knownAddresses: [Self.original], paidAddresses: [])
        #expect(LookAlikeRule().warning(for: Self.original, in: context) == nil)
    }

    @Test func `An unrelated address passes`() {
        let context = RecipientContext(knownAddresses: [Self.original], paidAddresses: [])
        #expect(LookAlikeRule().warning(for: Self.unrelated, in: context) == nil)
    }
}
