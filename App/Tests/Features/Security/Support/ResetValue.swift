import Storage
import Testing
@testable import widgets

struct ResetValue<Value: Equatable & Sendable>: ValueStoring {
    let storage: ResetStorage
    let step: ResetStorage.Step

    func load() async throws -> Value? { nil }

    func save(_ value: Value) async throws { Issue.record("A reset must not save a value.") }

    func delete() async throws { try await storage.delete(step) }

    func update<Result: Sendable>(_ change: @Sendable (inout Value?) throws -> Result) async throws -> Result {
        Issue.record("A reset must not change a value.")
        var value: Value?
        return try change(&value)
    }
}
