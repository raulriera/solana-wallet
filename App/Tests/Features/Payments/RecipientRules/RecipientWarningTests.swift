import Testing
@testable import widgets

struct RecipientWarningTests {
    private static let warnings = [RecipientWarning.lookAlike, .offCurve, .firstPayment]

    @Test func `Only misdirection warnings are serious`() {
        #expect(Self.warnings.map(\.isSerious) == [true, true, false])
    }
}
