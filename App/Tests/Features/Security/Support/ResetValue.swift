import Storage
import Testing
@testable import widgets

/// One saved value whose deletion the shared reset storage records in order.
struct ResetValue<Value: Equatable & Sendable>: ValueStoring {
    /// The storage that records every reset step.
    let storage: ResetStorage
    /// The step that deleting this value records.
    let step: ResetStorage.Step

    /// Returns no value.
    /// - Returns: `nil`.
    func load() async throws -> Value? { nil }

    /// Reports any save, because a reset only deletes.
    /// - Parameter value: The value the caller tried to save.
    func save(_ value: Value) async throws { Issue.record("A reset must not save a value.") }

    /// Records the deletion, unless this step fails.
    /// - Throws: A scripted failure.
    func delete() async throws { try await storage.delete(step) }

    /// Reports any change, because a reset only deletes.
    /// - Parameter change: The change the caller tried to make.
    /// - Returns: The change's result on no value, which is never saved.
    /// - Throws: The change's error.
    func update<Result: Sendable>(_ change: @Sendable (inout Value?) throws -> Result) async throws -> Result {
        Issue.record("A reset must not change a value.")
        var value: Value?
        return try change(&value)
    }
}
