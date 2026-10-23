import Foundation
import Testing
@testable import widgets

/// Checks that each recipient warning is told apart from the others, and which ones show as serious.
struct RecipientWarningTests {
    private static let warnings = [RecipientWarning.lookAlike, .offCurve, .firstPayment]

    /// No two warnings share an explanation or a symbol.
    @Test func `Each warning has its own explanation and symbol`() {
        #expect(Set(Self.warnings.map { String(localized: $0.message) }).count == Self.warnings.count)
        #expect(Set(Self.warnings.map(\.systemImage)).count == Self.warnings.count)
    }

    /// Warnings that can mean the payment goes somewhere unintended are serious; a first payment isn't.
    @Test func `Only misdirection warnings are serious`() {
        #expect(Self.warnings.map(\.isSerious) == [true, true, false])
    }
}
