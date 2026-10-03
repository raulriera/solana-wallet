import Foundation

/// Bridges the Settings bundle's switch to background preferences access.
nonisolated struct SettingsRecoveryRequest: RecoveryRequesting {
    static let key = "resetAppearance"

    /// The requested defaults domain could not be opened.
    enum Failure: Error { case unavailablePreferences }

    private let suiteName: String?

    /// Uses the application defaults domain or an isolated domain supplied by a test.
    /// - Parameter suiteName: A preferences suite, or `nil` for this application's settings.
    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// Reads the switch from Settings without opening theme packages.
    /// - Returns: `false` when the user has never requested recovery.
    /// - Throws: A preferences or cancellation error.
    @concurrent
    func isRequested() async throws -> Bool {
        try await CatalogIO.perform { _ in try defaults().bool(forKey: Self.key) }
    }

    /// Clears the switch after the caller has committed the reset.
    /// - Throws: A preferences or pre-write cancellation error.
    @concurrent
    func complete() async throws {
        try await CatalogIO.perform { checkCancellation in
            let defaults = try defaults()
            try checkCancellation()
            defaults.set(false, forKey: Self.key)
        }
    }

    /// Opens preferences only from the background I/O queue.
    /// - Returns: The configured defaults object, confined to the calling operation.
    /// - Throws: An unavailable-domain error.
    private func defaults() throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw Failure.unavailablePreferences }
        return defaults
    }
}
