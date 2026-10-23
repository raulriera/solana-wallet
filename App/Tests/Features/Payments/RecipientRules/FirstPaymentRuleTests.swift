import Testing
import Transactions
@testable import widgets

/// Checks that the first-payment rule notes only addresses the person never paid.
struct FirstPaymentRuleTests {
    private static let paid = try! Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
    private static let unpaid = try! Address("F3sVqBYJWSBdbsMtZes3AEKkBaiHHokhENFWA1PoMFSf")

    /// An address the person never paid gets the note; one they paid doesn't.
    @Test func `Only unpaid addresses get the note`() {
        let context = RecipientContext(knownAddresses: [Self.paid], paidAddresses: [Self.paid])
        #expect(FirstPaymentRule().warning(for: Self.unpaid, in: context) == .firstPayment)
        #expect(FirstPaymentRule().warning(for: Self.paid, in: context) == nil)
    }
}
