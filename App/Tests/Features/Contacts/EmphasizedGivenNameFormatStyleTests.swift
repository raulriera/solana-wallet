import Foundation
import Testing
@testable import widgets

struct EmphasizedGivenNameFormatStyleTests {
    @Test(arguments: [("Account 2", ["Account"]), ("123", [])])
    func `A name keeps its text and emphasizes only its given name`(name: String, emphasized: [String]) {
        let formatted = EmphasizedGivenNameFormatStyle.emphasizedGivenName.format(name)
        let emphasizedRuns = formatted.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
        #expect(String(formatted.characters) == name)
        #expect(emphasizedRuns.map { String(formatted[$0.range].characters) } == emphasized)
    }
}
