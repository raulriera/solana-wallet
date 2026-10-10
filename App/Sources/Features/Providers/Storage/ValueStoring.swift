/// A value saved on this device, such as an API key or a setting.
nonisolated protocol ValueStoring<Value>: Sendable {
    /// The type of the saved value.
    associatedtype Value: Sendable

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
}
