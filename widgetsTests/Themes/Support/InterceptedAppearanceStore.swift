import Foundation
@testable import widgets

/// Retains real storage behavior while delaying delivery of one read for ordering tests.
nonisolated struct InterceptedAppearanceStore: AppearanceStoring {
    /// Delays or fails delivery after the underlying store has loaded its snapshot.
    typealias LoadHook = @Sendable () async throws -> Void

    let base: any AppearanceStoring
    let afterLoad: LoadHook

    /// Wraps a real store with a deterministic completion barrier.
    /// - Parameters:
    ///   - base: The real store that persists and retrieves preferences.
    ///   - afterLoad: A test handshake after reading, before returning the snapshot.
    init(base: any AppearanceStoring, afterLoad: @escaping LoadHook) {
        self.base = base
        self.afterLoad = afterLoad
    }

    /// Reads real state and holds its delivery at the test's barrier.
    /// - Returns: The original snapshot, even if another operation commits while delayed.
    /// - Throws: The store or barrier error.
    func load() async throws -> AppearanceSnapshot {
        let snapshot = try await base.load()
        try await afterLoad()
        return snapshot
    }

    /// Forwards a selection without delaying its committed result.
    /// - Parameters:
    ///   - themeID: The selected identity, or `nil` to restore inheritance.
    ///   - scope: The application or wallet preference to change.
    /// - Returns: The real store's committed snapshot.
    /// - Throws: The underlying store error.
    func select(_ themeID: UUID?, for scope: AppearancePreferences.Scope) async throws -> AppearanceSnapshot {
        try await base.select(themeID, for: scope)
    }

    /// Forwards recovery without changing its storage semantics.
    /// - Returns: The real store's reset snapshot.
    /// - Throws: The underlying store error.
    func reset() async throws -> AppearanceSnapshot {
        try await base.reset()
    }
}
