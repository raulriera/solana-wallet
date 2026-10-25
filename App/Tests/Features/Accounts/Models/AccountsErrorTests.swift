import Foundation
import Testing
@testable import widgets

/// Verifies that each Settings > Accounts error explains itself and says whether the alert repeats the change.
@MainActor
struct AccountsErrorTests {
    /// Every error has an alert title and explanation.
    /// - Parameter error: The error.
    @Test(arguments: [AccountsError.notAdded, .recoveryUnavailable, .notRenamed, .notDeleted])
    func `Each error explains itself`(_ error: AccountsError) throws {
        let title = try #require(error.errorDescription)
        let message = try #require(error.recoverySuggestion)

        #expect(!title.isEmpty)
        #expect(!message.isEmpty)
    }

    /// Only an addition repeats from its alert: a missing recovery phrase stays missing, a rename keeps its typed name
    /// on screen, and a deleted account's row stays to delete again.
    /// - Parameters:
    ///   - error: The error.
    ///   - canRetry: Whether the alert offers Try Again.
    @Test(arguments: [(AccountsError.notAdded, true), (.recoveryUnavailable, false), (.notRenamed, false),
                      (.notDeleted, false)])
    func `Only an addition tries again`(_ error: AccountsError, canRetry: Bool) {
        #expect(error.canRetry == canRetry)
    }
}
