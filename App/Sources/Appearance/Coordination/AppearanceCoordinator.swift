import Foundation
import Observation

/// A coordinator that loads, saves, and publishes theme selections.
@MainActor @Observable final class AppearanceCoordinator: AppearanceCoordinating {
    private(set) var snapshot: AppearanceSnapshot?
    private let store: any AppearanceStoring
    private let recovery: (any RecoveryRequesting)?
    @ObservationIgnored private var activation: Task<Void, any Error>?

    /// Creates a coordinator.
    ///
    /// - Parameters:
    ///   - store: The store that saves the selections.
    ///   - recovery: The source of reset requests from Settings, or `nil` for none.
    init(store: any AppearanceStoring, recovery: (any RecoveryRequesting)?) {
        self.store = store
        self.recovery = recovery
    }

    func activate() async throws {
        if let activation { return try await activation.value }
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

    func reload() async throws {
        publish(try await store.load())
    }

    func restart() async throws {
        snapshot = nil
        try await reload()
    }

    func select(_ themeID: UUID?, for scope: AppearancePreferences.Scope) async throws {
        if let activation { try await activation.value }
        publish(try await store.select(themeID, for: scope))
    }

    func forget(_ themeID: UUID) async throws {
        if let activation { try await activation.value }
        publish(try await store.forget(themeID))
    }

    /// Clears and publishes every theme selection.
    ///
    /// - Throws: A storage or cancellation error.
    func reset() async throws {
        publish(try await store.reset())
    }

    /// Publishes a snapshot unless a newer one is already published.
    ///
    /// - Parameter value: The snapshot from the store.
    private func publish(_ value: AppearanceSnapshot) {
        guard snapshot.map({ value.revision > $0.revision }) ?? true else { return }
        snapshot = value
    }
}
