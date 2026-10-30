public import Foundation

/// A coding that keeps a value as JSON.
public struct JSONCoding<Value: Codable & Equatable & Sendable>: ValueCoding {
    /// Creates a coding that keeps values as JSON.
    public init() {}

    public func encode(_ value: Value) throws -> Data {
        try JSONEncoder().encode(value)
    }

    public func decode(_ data: Data) -> Value? {
        try? JSONDecoder().decode(Value.self, from: data)
    }
}

extension ValueCoding {
    /// Returns a coding that keeps a value of the given type as JSON.
    ///
    /// - Parameter type: The type of the saved value.
    /// - Returns: A coding that keeps the value as JSON.
    public static func json<Saved>(_ type: Saved.Type) -> Self where Self == JSONCoding<Saved> {
        JSONCoding()
    }
}
