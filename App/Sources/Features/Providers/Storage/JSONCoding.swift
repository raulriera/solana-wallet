import Foundation

/// Keeps a value as JSON.
nonisolated struct JSONCoding<Value: Codable & Sendable>: ValueCoding {
    /// Converts a value to JSON.
    /// - Parameter value: The value to save.
    /// - Returns: The value's JSON.
    /// - Throws: An encoding error if the value can't be represented as JSON.
    func encode(_ value: Value) throws -> Data {
        try JSONEncoder().encode(value)
    }

    /// Converts JSON back to a value.
    /// - Parameter data: The kept JSON.
    /// - Returns: The value, or `nil` when the bytes aren't JSON for this type.
    func decode(_ data: Data) -> Value? {
        try? JSONDecoder().decode(Value.self, from: data)
    }
}

nonisolated extension ValueCoding {
    /// Keeps a value of the given type as JSON.
    /// - Parameter type: The type of the saved value.
    /// - Returns: A coding that keeps the value as JSON.
    static func json<Saved>(_ type: Saved.Type) -> Self where Self == JSONCoding<Saved> {
        JSONCoding()
    }
}
