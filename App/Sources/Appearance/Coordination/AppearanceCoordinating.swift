import Foundation
import Observation

/// Shared presentation state for application and wallet appearance selections.
@MainActor protocol AppearanceCoordinating: AnyObject, Observable {
    var snapshot: AppearanceSnapshot? { get }

    /// Applies pending Settings recovery before loading appearance when a window becomes active.
    /// Concurrent activations share the same operation, which survives individual window cancellation.
    /// - Throws: A storage or preferences error, leaving failed recovery requests enabled.
    func activate() async throws

    /// Refreshes cached metadata at startup and after successful catalog mutations.
    /// - Throws: A storage or cancellation error, preserving the previous snapshot.
    func reload() async throws

    /// Forgets the cached selections and loads them again after the app deletes its saved data, which starts the
    /// stored revision over.
    /// - Throws: A storage or cancellation error, leaving the original appearance.
    func restart() async throws

    /// Persists a selection and publishes the committed state to all consuming windows.
    /// - Parameters:
    ///   - themeID: The selected identity, or `nil` to restore inheritance/original appearance.
    ///   - scope: The application default or a stable wallet identity.
    /// - Throws: A selection, storage, or cancellation error without an optimistic UI change.
    func select(_ themeID: UUID?, for scope: AppearancePreferences.Scope) async throws

    /// Persists that no scope uses a theme and publishes the committed state to all consuming windows.
    /// - Parameter themeID: The theme that the application and every wallet stop using.
    /// - Throws: A storage or cancellation error without an optimistic UI change.
    func forget(_ themeID: UUID) async throws
}
