import Foundation
import Testing
import Transactions
@testable import widgets

/// Checks how recent payments are identified.
struct RecentPaymentTests {
    /// Each address keeps one latest payment, so its address identifies it.
    @Test func `A recent payment is identified by its address`() {
        let payment = RecentPayment(address: ContactsFixtures.recent, date: .now)
        #expect(payment.id == ContactsFixtures.recent.value)
    }
}
