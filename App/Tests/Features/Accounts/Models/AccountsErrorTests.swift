import Foundation
import Testing
@testable import widgets

@MainActor
struct AccountsErrorTests {
    @Test(arguments: [(AccountsError.notAdded, true), (.recoveryUnavailable, false), (.notRenamed, false),
                      (.notDeleted, false)])
    func `Only an addition tries again`(_ error: AccountsError, canRetry: Bool) {
        #expect(error.canRetry == canRetry)
    }
}
