import Testing
import Transactions
@testable import widgets

struct RecipientClassifierTests {
    private static let flagged = try! Address("EXKmNaFvM61XU4RHuh8moR67QArXabU4NzW5yyPfyBK9")
    private static let context = RecipientContext(knownAddresses: [try! Address("EXKmNaFvM61XU4RHuh8moR67QArXabUBNzW5yyPfyBK9")], paidAddresses: [])

    @Test func `Warnings follow the rule order`() {
        #expect(RecipientClassifier(rules: [.lookAlike, .programAddress]).warnings(for: Self.flagged, in: Self.context)
            == [.lookAlike, .offCurve])
        #expect(RecipientClassifier(rules: [.programAddress, .lookAlike]).warnings(for: Self.flagged, in: Self.context)
            == [.offCurve, .lookAlike])
    }

    @Test func `The review adds the first-payment note to the entry's checks`() throws {
        let unpaid = try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
        let context = RecipientContext(knownAddresses: [], paidAddresses: [])
        #expect(RecipientClassifier.entry.warnings(for: unpaid, in: context) == [])
        #expect(RecipientClassifier.review.warnings(for: unpaid, in: context) == [.firstPayment])
    }
}
