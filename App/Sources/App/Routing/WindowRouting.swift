import Foundation
import Observation

/// Routes one window independently of other windows and feature workflows.
@MainActor
protocol WindowRouting: AnyObject, Observable {
    /// The root destination and, when present, this window's selected account.
    var destination: WindowDestination { get }

    /// Opens an account whose recovery and public metadata have already been saved.
    ///
    /// The caller completes persistence before routing. The router performs no storage
    /// operations and never receives recovery material.
    /// - Parameter accountID: The persisted account to select in this window.
    func showWallet(accountID: UUID)
}
