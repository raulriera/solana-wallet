public import Foundation

/// A coding that keeps text as its UTF-8 bytes.
public struct UTF8Coding: ValueCoding {
    /// Creates a coding that keeps text as UTF-8.
    public init() {}

    public func encode(_ value: String) -> Data {
        Data(value.utf8)
    }

    public func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }
}

extension ValueCoding where Self == UTF8Coding {
    public static var utf8: UTF8Coding { UTF8Coding() }
}
