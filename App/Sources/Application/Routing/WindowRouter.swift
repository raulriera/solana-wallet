import Foundation
import Observation

/// Owns the root destination of one window, independently of other windows.
@MainActor
@Observable
final class WindowRouter: WindowRouting {
    private(set) var destination: WindowDestination

    /// Creates independent routing state with the destination chosen by the caller.
    /// - Parameter initialDestination: The starting root, referencing an already-persisted account when showing a wallet.
    init(initialDestination: WindowDestination) {
        destination = initialDestination
    }

    /// Replaces this window's root destination.
    ///
    /// - Parameter destination: The new root.
    func route(to destination: WindowDestination) {
        self.destination = destination
    }
}
