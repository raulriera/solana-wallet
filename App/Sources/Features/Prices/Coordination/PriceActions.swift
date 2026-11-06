import Foundation

/// The commands that price provider controls run.
@MainActor protocol PriceActions: AnyObject {
    /// Chooses the price provider in use.
    ///
    /// - Parameter provider: The price provider to use.
    func select(_ provider: PriceSettings.Provider)

    /// Shows a custom price server's details.
    ///
    /// - Parameter url: The price server whose details to show.
    func showDetails(of url: URL)

    /// Opens the screen that checks and adds a custom price server.
    func addServer()

    /// Deletes a confirmed custom price server.
    ///
    /// - Parameter url: The price server to delete.
    func remove(_ url: URL)
}
