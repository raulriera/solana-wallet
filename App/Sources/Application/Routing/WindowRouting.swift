import Observation

/// Routes one window independently of other windows and feature workflows.
@MainActor
protocol WindowRouting: AnyObject, Observable {
    /// The root destination and, when present, this window's selected account.
    var destination: WindowDestination { get }

    /// Replaces this window's root destination.
    ///
    /// Callers save the account before routing to it.
    ///
    /// - Parameter destination: The root to present in this window.
    func route(to destination: WindowDestination)
}
