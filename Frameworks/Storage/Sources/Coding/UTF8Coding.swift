public import Foundation

/// Keeps text as its UTF-8 bytes.
public struct UTF8Coding: ValueCoding {
    /// Creates a coding that keeps text as UTF-8.
    public init() {}

    /// Converts text to its UTF-8 bytes.
    /// - Parameter value: The text to save.
    /// - Returns: The text's UTF-8 bytes.
    public func encode(_ value: String) -> Data {
        Data(value.utf8)
    }

    /// Converts UTF-8 bytes back to text.
    /// - Parameter data: The kept bytes.
    /// - Returns: The text, or `nil` when the bytes aren't valid UTF-8.
    public func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }
}

extension ValueCoding where Self == UTF8Coding {
    /// Keeps text as its UTF-8 bytes.
    public static var utf8: UTF8Coding { UTF8Coding() }
}
