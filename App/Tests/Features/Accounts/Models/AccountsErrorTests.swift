import Foundation
import Testing
@testable import widgets

@MainActor
struct AccountsErrorTests {
    @Test(arguments: [AccountsError.notAdded, .recoveryUnavailable, .notRenamed, .notDeleted])
    func `Each error explains itself`(_ error: AccountsError) throws {
        let title = try #require(error.errorDescription)
        let message = try #require(error.recoverySuggestion)

        #expect(!title.isEmpty)
        #expect(!message.isEmpty)
    }

    @Test(arguments: [(AccountsError.notAdded, true), (.recoveryUnavailable, false), (.notRenamed, false),
                      (.notDeleted, false)])
    func `Only an addition tries again`(_ error: AccountsError, canRetry: Bool) {
        #expect(error.canRetry == canRetry)
    }
}
