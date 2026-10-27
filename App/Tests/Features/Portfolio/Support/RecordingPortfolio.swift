import Observation
import Portfolio
import Transactions
@testable import widgets

/// Records observations and refreshes in place of the window's portfolio, and shows set holdings, without any
/// request.
@MainActor
@Observable
final class RecordingPortfolio: PortfolioCoordinating {
    var holdings: [Holding] = []
    /// The wallets that active scenes observed, in order.
    private(set) var observedOwners: [String?] = []
    /// Whether an active scene's task is observing.
    private(set) var isObserving = false
    /// How many times a workflow asked to read the balances again.
    private(set) var refreshes = 0

    var error: PortfolioError?

    /// Records an active scene's observation, which lasts until the view task is cancelled, as the window's
    /// portfolio's does.
    /// - Parameters:
    ///   - account: The selected account, whose address is recorded.
    ///   - isActive: Whether the scene is active.
    func observe(for account: Account?, isActive: Bool) async {
        guard isActive else { return }
        observedOwners.append(account?.address.value)
        isObserving = true
        // Nothing resumes the suspension, so observation ends only when the view task is cancelled.
        await Suspension().suspend()
        isObserving = false
    }

    /// Counts refreshes, such as the one after a payment lands.
    func refresh() async {
        refreshes += 1
    }
}
