import Testing
import Transactions
@testable import widgets

struct LookAlikeRuleTests {
    private static let original = try! Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
    private static let lookAlike = try! Address("6d8tEyrqPq1bEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
    private static let unrelated = try! Address("F3sVqBYJWSBdbsMtZes3AEKkBaiHHokhENFWA1PoMFSf")

    @Test(arguments: [
        (Self.lookAlike, Optional(RecipientWarning.lookAlike)),
        (Self.original, nil),
        (Self.unrelated, nil),
    ])
    func `Only an address that differs from a known one in the middle is a look-alike`(
        address: Address, warning: RecipientWarning?
    ) {
        let context = RecipientContext(knownAddresses: [Self.original], paidAddresses: [])
        #expect(LookAlikeRule().warning(for: address, in: context) == warning)
    }
}
