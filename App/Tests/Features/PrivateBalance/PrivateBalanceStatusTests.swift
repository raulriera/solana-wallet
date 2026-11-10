import Privacy
import Testing
@testable import widgets

struct PrivateBalanceStatusTests {
    @Test
    func `Statuses are equal only with the same case and balance`() {
        let statuses: [PrivateBalanceStatus] = [
            .off(isRegistered: false), .off(isRegistered: true), .unavailable, .unregistered,
            .balance(available: 0, pending: 0), .balance(available: 1, pending: 0),
            .balance(available: 0, pending: 1), .balance(available: 1, pending: 0, of: .token(.devnetUSDC)),
        ]

        for (index, status) in statuses.enumerated() {
            for (otherIndex, other) in statuses.enumerated() {
                #expect((status == other) == (index == otherIndex))
            }
        }
    }

    @Test
    func `An empty sync state has nothing available or pending`() {
        #expect(PrivateBalanceStatus.balance(of: NoteSyncState()) == .balance(available: 0, pending: 0))
    }

    @Test
    func `A recorded deposit is pending`() throws {
        let state = try NoteSyncState().recording(depositOf: 5_000, signature: "deposit")

        #expect(PrivateBalanceStatus.balance(of: state) == .balance(available: 0, pending: 5_000))
    }

    @Test
    func `A recorded token deposit is pending in its token only`() throws {
        let state = try NoteSyncState().recording(depositOf: 5_000, of: .devnetUSDC, signature: "deposit")
        let status = PrivateBalanceStatus.balance(of: state)

        #expect(status == .balance(available: 0, pending: 5_000, of: .token(.devnetUSDC)))
        #expect(status.balance(of: .sol) == .zero)
    }

    @Test(arguments: [PrivateBalanceStatus.off(isRegistered: true), .unavailable, .unregistered])
    func `Statuses without a balance have no asset balance`(status: PrivateBalanceStatus) {
        #expect(status.balance(of: .sol) == nil)
    }
}
