import Foundation
import Testing
@testable import widgets

/// Checks that each recipient warning is told apart from the others.
struct RecipientWarningTests {
    /// No two warnings share an explanation or a symbol.
    @Test func `Each warning has its own explanation and symbol`() {
        let warnings = [RecipientWarning.lookAlike, .offCurve]
        #expect(Set(warnings.map { String(localized: $0.message) }).count == warnings.count)
        #expect(Set(warnings.map(\.systemImage)).count == warnings.count)
    }
}
