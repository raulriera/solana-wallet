import Foundation
import Testing
@testable import widgets

/// Checks that each recipient rejection has its own explanation.
struct RecipientRejectionTests {
    /// No two rejections share an explanation.
    @Test func `Each rejection explains itself differently`() {
        let messages = [RecipientRejection.notAddress, .sendingAccount, .alreadySaved].map { String(localized: $0.message) }
        #expect(Set(messages).count == messages.count)
    }
}
