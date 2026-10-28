import Observation

/// One window's observation of its wallet.
@MainActor
protocol PortfolioCoordinating: AnyObject, Observable {
    /// Observes the selected account's wallet for the lifetime of the calling view task.
    ///
    /// Use the account and scene activity as the view task's identity. Cancellation,
    /// an inactive scene, or a replacement account stops observation.
    /// - Parameters:
    ///   - account: The selected account, or `nil` when no wallet is selected.
    ///   - isActive: Whether the presenting scene is active.
    func observe(for account: Account?, isActive: Bool) async

    /// Reloads the active wallet, awaiting completion for pull-to-refresh.
    ///
    /// Every window that observes the wallet receives the results, and a disconnected observation connects again.
    /// Cancelling a call stops its wait, not the read. Inactive calls do nothing.
    func refresh() async
}
