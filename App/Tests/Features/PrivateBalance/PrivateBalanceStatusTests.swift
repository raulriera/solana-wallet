import Privacy
import Testing
@testable import widgets

struct PrivateBalanceStatusTests {
    @Test
    func `A recorded token deposit is pending in its token only`() throws {
        let state = try NoteSyncState().recording(depositOf: 5_000, of: .token(.devnetUSDC), signature: "deposit")
        let status = PrivateBalanceStatus.balance(of: state)

        #expect(status == .balance(available: 0, pending: 5_000, of: .token(.devnetUSDC)))
        #expect(status.balance(of: .nativeSOL) == .zero)
    }

    @Test
    func `Statuses without a balance have no asset balance`() {
        #expect(PrivateBalanceStatus.unavailable.balance(of: .nativeSOL) == nil)
    }
}
