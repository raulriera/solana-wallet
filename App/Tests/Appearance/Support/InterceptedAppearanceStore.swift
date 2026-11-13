import Foundation
@testable import widgets

nonisolated struct InterceptedAppearanceStore: AppearanceStoring {
    typealias LoadHook = @Sendable () async throws -> Void

    let base: any AppearanceStoring
    let afterLoad: LoadHook

    init(base: any AppearanceStoring, afterLoad: @escaping LoadHook) {
        self.base = base
        self.afterLoad = afterLoad
    }

    func load() async throws -> AppearanceSnapshot {
        let snapshot = try await base.load()
        try await afterLoad()
        return snapshot
    }

    func select(_ themeID: UUID?) async throws -> AppearanceSnapshot {
        try await base.select(themeID)
    }

    func select(_ layout: CardStyle.Layout) async throws -> AppearanceSnapshot {
        try await base.select(layout)
    }

    func forget(_ themeID: UUID) async throws -> AppearanceSnapshot {
        try await base.forget(themeID)
    }

    func reset() async throws -> AppearanceSnapshot {
        try await base.reset()
    }
}
