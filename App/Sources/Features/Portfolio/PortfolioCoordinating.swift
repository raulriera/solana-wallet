import Observation
import Portfolio

/// The portfolio presentation's lifetime and explicit refresh boundary.
@MainActor
protocol PortfolioCoordinating: AnyObject, Observable {
    /// The selected wallet's latest state, or `nil` before any data is available.
    var update: Update? { get }
    /// Why the latest update failed, or `nil` when it didn't.
    var failure: PortfolioFailure? { get }

    /// Observes the selected wallet for the lifetime of the calling view task.
    ///
    /// Use the wallet and scene activity as the view task's identity. Cancellation,
    /// an inactive scene, or a replacement wallet stops observation and manual refreshes.
    /// - Parameters:
    ///   - owner: The selected public address, or `nil` when no wallet is selected.
    ///   - isActive: Whether the presenting scene is active.
    func observe(for owner: String?, isActive: Bool) async

    /// Reloads the active wallet, awaiting completion for pull-to-refresh.
    ///
    /// Overlapping calls share one operation. Cancellation detaches that operation;
    /// the confirmed-change observation remains active. Inactive calls do nothing.
    func refresh() async
}
