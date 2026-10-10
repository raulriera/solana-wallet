import Testing
@testable import widgets

/// One saved value whose deletion the shared reset storage records in order.
struct ResetValue<Value: Sendable>: ValueStoring {
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
}
