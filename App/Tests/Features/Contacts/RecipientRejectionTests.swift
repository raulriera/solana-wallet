import Foundation
import Testing
@testable import widgets

struct RecipientRejectionTests {
    @Test func `Each rejection explains itself differently`() {
        let messages = [RecipientRejection.notAddress, .sendingAccount, .alreadySaved].map { String(localized: $0.message) }
        #expect(Set(messages).count == messages.count)
    }
}
