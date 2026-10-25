/// A value saved on this device, such as an API key or a setting.
public protocol ValueStoring<Value>: Sendable {
    /// The type of the saved value.
    associatedtype Value: Equatable & Sendable

    /// Reads the saved value.
    /// - Returns: The value, or `nil` before one is saved.
    /// - Throws: A storage or cancellation error.
    func load() async throws -> Value?

    /// Saves a value, replacing any value already saved.
    /// - Parameter value: The new value.
    /// - Throws: A storage or cancellation error.
    func save(_ value: Value) async throws

    /// Deletes the saved value.
    /// - Throws: A storage or cancellation error. A missing value is already deleted.
    func delete() async throws

    /// Reads, changes, and saves the value in one step, so changes made at the same time don't overwrite each other.
    /// - Parameter change: Changes the saved value, or `nil` before one is saved; setting `nil` deletes the value,
    ///   and an unchanged value isn't saved again.
    /// - Returns: The change's result.
    /// - Throws: The change's error, which keeps the saved value, or a storage or cancellation error.
    func update<Result: Sendable>(_ change: @escaping @Sendable (inout Value?) throws -> Result) async throws -> Result
}
