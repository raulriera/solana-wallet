import Foundation
import Observation
import Testing
@testable import widgets

/// Shared appearance whose restart the shared reset storage records in order.
@MainActor
@Observable
final class ResetAppearance: AppearanceCoordinating {
    /// The storage that records every reset step.
    @ObservationIgnored let storage: ResetStorage
    let snapshot: AppearanceSnapshot? = nil

    /// Records into one test's storage.
    /// - Parameter storage: The storage that records every reset step.
    init(storage: ResetStorage) {
        self.storage = storage
    }

    /// Reports any activation, because a reset only restarts appearance.
    func activate() async throws { Issue.record("A reset must not activate appearance.") }

    /// Reports any reload, because a reset restarts appearance instead.
    func reload() async throws { Issue.record("A reset must restart appearance, not reload it.") }

    /// Records the restart, unless this step fails.
    /// - Throws: A scripted failure.
    func restart() async throws { try await storage.delete(.appearance) }

    /// Reports any selection, because a reset only deletes.
    /// - Parameters:
    ///   - themeID: The theme the caller selected.
    ///   - scope: The scope the caller named.
    func select(_ themeID: UUID?, for scope: AppearancePreferences.Scope) async throws {
        Issue.record("A reset must not select a theme.")
    }

    /// Reports any forgetting, because a reset only deletes.
    /// - Parameter themeID: The theme the caller forgot.
    func forget(_ themeID: UUID) async throws { Issue.record("A reset must not forget a theme.") }
}
