import Foundation
@testable import widgets

/// Keeps one value in memory in place of device storage, optionally failing or suspending each save.
actor StoredValue<Value: Sendable>: ValueStoring {
    private(set) var value: Value?
    private let failsSaving: Bool
    private let gate: Suspension?

    /// Creates storage for one test.
    /// - Parameters:
    ///   - value: The value saved before the test starts, if any.
    ///   - failsSaving: Whether saves throw instead of recording the value.
    ///   - gate: An optional suspension after a save records its value, for cancellation checks.
    init(_ value: Value? = nil, failsSaving: Bool = false, gate: Suspension? = nil) {
        self.value = value
        self.failsSaving = failsSaving
        self.gate = gate
    }

    /// Returns the recorded value.
    /// - Returns: The value, or `nil` before one is saved.
    func load() -> Value? { value }

    /// Records the value, or throws when this storage is configured to fail.
    /// - Parameter value: The value to save.
    /// - Throws: A write error when `failsSaving` is set.
    func save(_ value: Value) async throws {
        if failsSaving { throw CocoaError(.fileWriteUnknown) }
        self.value = value
        await gate?.suspend()
    }

    /// Forgets the recorded value.
    func delete() {
        value = nil
    }
}
