import Foundation
import Observation

/// Keeps lightweight selections in memory; package loading and rendering are separate concerns.
@MainActor @Observable final class AppearanceCoordinator: AppearanceCoordinating {
    private(set) var snapshot: AppearanceSnapshot?
    private let store: any AppearanceStoring
    private let recovery: (any RecoveryRequesting)?
    @ObservationIgnored private var activation: Task<Void, any Error>?

    /// Creates one shared coordinator for windows using the same catalog configuration.
    /// - Parameters:
    ///   - store: Persistent preferences whose I/O runs outside the main actor.
    ///   - recovery: The Settings request source, omitted by consumers without Settings integration.
    init(store: any AppearanceStoring, recovery: (any RecoveryRequesting)? = nil) {
        self.store = store
        self.recovery = recovery
    }

    /// Applies a pending one-time reset before publishing the window's initial appearance.
    /// - Throws: A storage or preferences error. A failed reset retains its request for the next activation.
    func activate() async throws {
        if let activation { return try await activation.value }
        // App-owned work must finish even if one participating scene becomes inactive.
        let operation = Task {
            if let recovery, try await recovery.isRequested() {
                try await reset()
                try await recovery.complete()
            } else {
                try await reload()
            }
        }
        activation = operation
        defer { activation = nil }
        try await operation.value
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
        if let activation { try await activation.value }
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
