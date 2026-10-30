import Testing
import Transactions
@testable import widgets

struct FirstPaymentRuleTests {
    private static let paid = try! Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
    private static let unpaid = try! Address("F3sVqBYJWSBdbsMtZes3AEKkBaiHHokhENFWA1PoMFSf")

    @Test func `Only unpaid addresses get the note`() {
        let context = RecipientContext(knownAddresses: [Self.paid], paidAddresses: [Self.paid])
        #expect(FirstPaymentRule().warning(for: Self.unpaid, in: context) == .firstPayment)
        #expect(FirstPaymentRule().warning(for: Self.paid, in: context) == nil)
    }
}
