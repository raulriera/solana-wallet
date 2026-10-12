import Foundation
@testable import widgets

/// Keeps one value in memory in place of device storage, optionally failing each read or save, or suspending each save.
actor StoredValue<Value: Equatable & Sendable>: ValueStoring {
    private(set) var value: Value?
    private var failsLoading: Bool
    private let failsSaving: Bool
    private let gate: Suspension?

    /// Creates storage for one test.
    /// - Parameters:
    ///   - value: The value saved before the test starts, if any.
    ///   - failsLoading: Whether reads throw instead of returning the value.
    ///   - failsSaving: Whether saves throw instead of recording the value.
    ///   - gate: An optional suspension after a save records its value, for cancellation checks.
    init(_ value: Value? = nil, failsLoading: Bool = false, failsSaving: Bool = false, gate: Suspension? = nil) {
        self.value = value
        self.failsLoading = failsLoading
        self.failsSaving = failsSaving
        self.gate = gate
    }

    /// Returns the recorded value, or throws when this storage is configured to fail reads.
    /// - Returns: The value, or `nil` before one is saved.
    /// - Throws: A read error when `failsLoading` is set.
    func load() throws -> Value? {
        if failsLoading { throw CocoaError(.fileReadUnknown) }
        return value
    }

    /// Makes later reads throw, as storage that becomes unreadable does.
    func failLoading() {
        failsLoading = true
    }

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

    /// Changes the recorded value in one step, or throws when this storage is configured to fail.
    /// - Parameter change: Changes the recorded value; an unchanged value isn't saved again.
    /// - Returns: The change's result.
    /// - Throws: The change's error, a read error when `failsLoading` is set, or a write error when `failsSaving` is
    ///   set and the value changed.
    func update<Result: Sendable>(_ change: @Sendable (inout Value?) throws -> Result) async throws -> Result {
        var changed = try load()
        let result = try change(&changed)
        guard changed != value else { return result }
        if failsSaving { throw CocoaError(.fileWriteUnknown) }
        value = changed
        await gate?.suspend()
        return result
    }
}
