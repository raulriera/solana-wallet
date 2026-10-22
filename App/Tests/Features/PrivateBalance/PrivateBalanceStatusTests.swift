import Privacy
import Testing
@testable import widgets

/// Verifies that refresh statuses compare by case and amounts, and that synced notes split into available and pending
/// lamports.
struct PrivateBalanceStatusTests {
    /// Statuses are equal only with the same case and the same available and pending lamports.
    @Test
    func `Statuses are equal only with the same case and balance`() {
        let statuses: [PrivateBalanceStatus] = [
            .off(isRegistered: false), .off(isRegistered: true), .unavailable, .unregistered,
            .balance(available: 0, pending: 0), .balance(available: 1, pending: 0),
            .balance(available: 0, pending: 1),
        ]

        for (index, status) in statuses.enumerated() {
            for (otherIndex, other) in statuses.enumerated() {
                #expect((status == other) == (index == otherIndex))
            }
        }
    }

    /// An empty sync state is a zero balance.
    @Test
    func `An empty sync state has nothing available or pending`() {
        #expect(PrivateBalanceStatus.balance(of: NoteSyncState()) == .balance(available: 0, pending: 0))
    }

    /// A recorded deposit that the indexer hasn't reported is pending, not available.
    @Test
    func `A recorded deposit is pending`() throws {
        let state = try NoteSyncState().recording(depositOf: 5_000, signature: "deposit")

        #expect(PrivateBalanceStatus.balance(of: state) == .balance(available: 0, pending: 5_000))
    }
}
