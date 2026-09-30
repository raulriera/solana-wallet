import Foundation
import Observation

/// Keeps lightweight selections in memory; package loading and rendering are separate concerns.
@MainActor @Observable final class AppearanceCoordinator: AppearanceCoordinating {
    private(set) var snapshot: AppearanceSnapshot?
    private let store: any AppearanceStoring

    /// Creates one shared coordinator for windows using the same catalog configuration.
    /// - Parameter store: Persistent preferences whose I/O runs outside the main actor.
    init(store: any AppearanceStoring) {
        self.store = store
    }

    /// Reloads metadata after startup or a catalog change, ignoring older completions.
    /// - Throws: A storage or cancellation error without discarding cached state.
    func reload() async throws {
        publish(try await store.load())
    }

    /// Commits a selection before making it observable.
    /// - Parameters:
    ///   - themeID: The selected identity, or `nil` to clear this scope's selection.
    ///   - scope: The application default or wallet override.
    /// - Throws: A selection, storage, or cancellation error.
    func select(_ themeID: UUID?, for scope: AppearancePreferences.Scope) async throws {
        publish(try await store.select(themeID, for: scope))
    }

    /// Restores the original appearance everywhere after persistence succeeds.
    /// - Throws: A storage or cancellation error.
    func reset() async throws {
        publish(try await store.reset())
    }

    /// Prevents a delayed read or write response from rolling back newer window edits.
    /// - Parameter value: The snapshot returned by the shared persistent store.
    private func publish(_ value: AppearanceSnapshot) {
        guard snapshot.map({ value.revision > $0.revision }) ?? true else { return }
        snapshot = value
    }
}
