import Testing
@testable import widgets

/// Verifies that refresh statuses compare by case and, for a balance, by amount.
struct PrivateBalanceStatusTests {
    /// Statuses are equal only with the same case and the same balance.
    @Test
    func `Statuses are equal only with the same case and balance`() {
        let statuses: [PrivateBalanceStatus] = [.off, .unavailable, .unregistered, .lamports(0), .lamports(1)]

        for (index, status) in statuses.enumerated() {
            for (otherIndex, other) in statuses.enumerated() {
                #expect((status == other) == (index == otherIndex))
            }
        }
    }
}
