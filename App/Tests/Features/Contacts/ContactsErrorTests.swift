import Foundation
import Testing
@testable import widgets

/// Verifies that each Contacts error has an alert title and explanation.
struct ContactsErrorTests {
    /// The error explains itself in an alert.
    @Test
    func `A change that can't be saved explains itself`() throws {
        let title = try #require(ContactsError.unsaved.errorDescription)
        let message = try #require(ContactsError.unsaved.recoverySuggestion)

        #expect(!title.isEmpty)
        #expect(!message.isEmpty)
    }
}
