import Foundation
@testable import widgets

/// Records accepted provider keys in memory, optionally failing or suspending each save.
actor SavedKeys: ProviderKeyStoring {
    private(set) var saved: String?
    private let failsSaving: Bool
    private let gate: Suspension?

    /// Creates empty storage for one test.
    /// - Parameters:
    ///   - failsSaving: Whether saves throw instead of recording the key.
    ///   - gate: An optional suspension after a save records its key, for cancellation checks.
    init(failsSaving: Bool = false, gate: Suspension? = nil) {
        self.failsSaving = failsSaving
        self.gate = gate
    }

    /// Returns the most recently recorded key.
    /// - Returns: The key, or `nil` before one is saved.
    func key() -> String? { saved }

    /// Records the key, or throws when this storage is configured to fail.
    /// - Parameter key: The key the provider accepted.
    /// - Throws: A write error when `failsSaving` is set.
    func save(_ key: String) async throws {
        if failsSaving { throw CocoaError(.fileWriteUnknown) }
        saved = key
        await gate?.suspend()
    }
}
