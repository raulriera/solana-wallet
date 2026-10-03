import Observation

/// Routes one window independently of other windows and feature workflows.
@MainActor
protocol WindowRouting: AnyObject, Observable {
    /// The root destination and, when present, this window's selected account.
    var destination: WindowDestination { get }

    /// Replaces this window's root destination.
    ///
    /// Before routing to a wallet, the caller saves its recovery and public metadata.
    /// The router performs no storage operations and never receives recovery material.
    /// - Parameter destination: The root to present in this window.
    func route(to destination: WindowDestination)
}
