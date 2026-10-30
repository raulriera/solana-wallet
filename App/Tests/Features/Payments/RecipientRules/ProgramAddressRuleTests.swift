import Testing
import Transactions
@testable import widgets

struct ProgramAddressRuleTests {
    @Test(arguments: [
        ("EXKmNaFvM61XU4RHuh8moR67QArXabU4NzW5yyPfyBK9", RecipientWarning?.some(.offCurve)),
        ("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK", nil),
    ])
    func `Only addresses without a key are flagged`(text: String, warning: RecipientWarning?) throws {
        let context = RecipientContext(knownAddresses: [], paidAddresses: [])
        #expect(ProgramAddressRule().warning(for: try Address(text), in: context) == warning)
    }
}
