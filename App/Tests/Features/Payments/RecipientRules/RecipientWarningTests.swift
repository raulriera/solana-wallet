import Foundation
import Testing
@testable import widgets

struct RecipientWarningTests {
    private static let warnings = [RecipientWarning.lookAlike, .offCurve, .firstPayment]

    @Test func `Each warning has its own explanation and symbol`() {
        #expect(Set(Self.warnings.map { String(localized: $0.message) }).count == Self.warnings.count)
        #expect(Set(Self.warnings.map(\.systemImage)).count == Self.warnings.count)
    }

    @Test func `Only misdirection warnings are serious`() {
        #expect(Self.warnings.map(\.isSerious) == [true, true, false])
    }
}
