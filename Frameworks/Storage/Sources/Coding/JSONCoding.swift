public import Foundation

/// Keeps a value as JSON.
public struct JSONCoding<Value: Codable & Equatable & Sendable>: ValueCoding {
    /// Creates a coding that keeps values as JSON.
    public init() {}

    /// Converts a value to JSON.
    /// - Parameter value: The value to save.
    /// - Returns: The value's JSON.
    /// - Throws: An encoding error if the value can't be represented as JSON.
    public func encode(_ value: Value) throws -> Data {
        try JSONEncoder().encode(value)
    }

    /// Converts JSON back to a value.
    /// - Parameter data: The kept JSON.
    /// - Returns: The value, or `nil` when the bytes aren't JSON for this type.
    public func decode(_ data: Data) -> Value? {
        try? JSONDecoder().decode(Value.self, from: data)
    }
}

extension ValueCoding {
    /// Keeps a value of the given type as JSON.
    /// - Parameter type: The type of the saved value.
    /// - Returns: A coding that keeps the value as JSON.
    public static func json<Saved>(_ type: Saved.Type) -> Self where Self == JSONCoding<Saved> {
        JSONCoding()
    }
}
