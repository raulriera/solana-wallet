import Testing
import Transactions
@testable import widgets

/// Checks that the program address rule catches addresses no key exists for.
struct ProgramAddressRuleTests {
    /// An off-curve address belongs to a program; an on-curve one passes.
    /// - Parameters:
    ///   - text: The address.
    ///   - warning: The warning it gets, or `nil` when it passes.
    @Test(arguments: [
        ("EXKmNaFvM61XU4RHuh8moR67QArXabU4NzW5yyPfyBK9", RecipientWarning?.some(.offCurve)),
        ("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK", nil),
    ])
    func `Only addresses without a key are flagged`(text: String, warning: RecipientWarning?) throws {
        let context = RecipientContext(knownAddresses: [], paidAddresses: [])
        #expect(ProgramAddressRule().warning(for: try Address(text), in: context) == warning)
    }
}
