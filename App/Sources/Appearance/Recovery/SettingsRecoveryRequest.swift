import Foundation

/// A reset request read from the app's switch in Settings.
nonisolated struct SettingsRecoveryRequest: RecoveryRequesting {
    static let key = "resetAppearance"

    private let suiteName: String?

    /// Creates a request that reads a defaults suite.
    ///
    /// - Parameter suiteName: The defaults suite, or `nil` for the app's defaults.
    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    @concurrent
    func isRequested() async throws -> Bool {
        try await CatalogIO.perform { _ in try defaults().bool(forKey: Self.key) }
    }

    @concurrent
    func complete() async throws {
        try await CatalogIO.perform { checkCancellation in
            let defaults = try defaults()
            try checkCancellation()
            defaults.set(false, forKey: Self.key)
        }
    }

    /// Opens the defaults suite.
    ///
    /// - Returns: The defaults suite.
    /// - Throws: An unavailable-preferences error.
    private func defaults() throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw SettingsRecoveryRequestError.unavailablePreferences }
        return defaults
    }
}
