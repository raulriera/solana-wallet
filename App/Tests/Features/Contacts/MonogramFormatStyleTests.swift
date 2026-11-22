import Foundation
import Testing
import Transactions
@testable import widgets

struct MonogramFormatStyleTests {
    @Test(arguments: [("Adam Okon" as String?, "AO"), ("Account 12", "A12"), ("Rent 2024", "R"), (nil, "6D"), ("123", "6D")])
    func `A recipient abbreviates to its name's initials and trailing number, or else to its address's first two characters`(
        name: String?, monogram: String
    ) throws {
        let recipient = PaymentRecipient(address: try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
                                         name: name)
        #expect(MonogramFormatStyle.monogram.locale(Locale(identifier: "en_US")).format(recipient) == monogram)
    }
}

struct EmphasizedGivenNameFormatStyleTests {
    @Test(arguments: [("Adam Okon", ["Adam"]), ("Account 2", ["Account"]), ("123", [])])
    func `A name keeps its text and emphasizes only its given name`(name: String, emphasized: [String]) {
        let formatted = EmphasizedGivenNameFormatStyle.emphasizedGivenName.format(name)
        let emphasizedRuns = formatted.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
        #expect(String(formatted.characters) == name)
        #expect(emphasizedRuns.map { String(formatted[$0.range].characters) } == emphasized)
    }
}
