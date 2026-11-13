import Foundation
import Observation
import Testing
@testable import widgets

@MainActor
@Observable
final class ResetAppearance: AppearanceCoordinating {
    @ObservationIgnored let storage: ResetStorage
    let snapshot: AppearanceSnapshot? = nil

    init(storage: ResetStorage) {
        self.storage = storage
    }

    func activate() async throws { Issue.record("A reset must not activate appearance.") }

    func reload() async throws { Issue.record("A reset must restart appearance, not reload it.") }

    func restart() async throws { try await storage.delete(.appearance) }

    func select(_ themeID: UUID?) async throws {
        Issue.record("A reset must not select a theme.")
    }

    func select(_ layout: CardStyle.Layout) async throws {
        Issue.record("A reset must not select a token layout.")
    }

    func forget(_ themeID: UUID) async throws { Issue.record("A reset must not forget a theme.") }
}
