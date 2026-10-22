import Testing
import Transactions
@testable import widgets

/// Checks that the classifier keeps its rules' order and leaves out the rules that pass.
struct RecipientClassifierTests {
    /// Off the curve and shortening like a known address, so both rules flag it.
    private static let flagged = try! Address("EXKmNaFvM61XU4RHuh8moR67QArXabU4NzW5yyPfyBK9")
    private static let context = RecipientContext(knownAddresses: [try! Address("EXKmNaFvM61XU4RHuh8moR67QArXabUBNzW5yyPfyBK9")])

    /// Warnings come back in the order the screen lists its rules.
    @Test func `Warnings follow the rule order`() {
        #expect(RecipientClassifier(rules: [.lookAlike, .programAddress]).warnings(for: Self.flagged, in: Self.context)
            == [.lookAlike, .offCurve])
        #expect(RecipientClassifier(rules: [.programAddress, .lookAlike]).warnings(for: Self.flagged, in: Self.context)
            == [.offCurve, .lookAlike])
    }

    /// Rules that pass add nothing.
    @Test func `Passing rules add no warnings`() throws {
        let person = try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
        #expect(RecipientClassifier(rules: [.lookAlike, .programAddress]).warnings(for: person, in: Self.context) == [])
    }
}
