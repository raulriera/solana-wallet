public import Foundation

/// A type that converts a saved value to and from the bytes that a store keeps.
public protocol ValueCoding<Value>: Sendable {
    /// The type of the saved value.
    associatedtype Value: Equatable & Sendable

    /// Converts a value to the bytes to keep.
    ///
    /// - Parameter value: The value to save.
    /// - Returns: The bytes that represent the value.
    /// - Throws: An encoding error if the value can't be represented.
    func encode(_ value: Value) throws -> Data

    /// Converts kept bytes back to a value.
    ///
    /// - Parameter data: The kept bytes.
    /// - Returns: The value, or `nil` when the bytes don't represent one.
    func decode(_ data: Data) -> Value?
}
