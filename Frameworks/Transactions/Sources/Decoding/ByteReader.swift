import Foundation

/// A reader of little-endian fields from a byte array.
struct ByteReader {
    private let bytes: [UInt8]
    private let error: any Error
    private(set) var offset: Int

    /// Creates a reader.
    ///
    /// - Parameters:
    ///   - bytes: The bytes to read.
    ///   - offset: The position of the first byte to read.
    ///   - error: The error to throw when a read runs past the end of the input.
    init(_ bytes: [UInt8], at offset: Int = 0, error: any Error) {
        self.bytes = bytes
        self.offset = offset
        self.error = error
    }

    /// Reads an unsigned integer in its fixed-width little-endian representation.
    ///
    /// - Returns: The integer represented by the next bytes.
    /// - Throws: The reader's error if the input is truncated.
    mutating func integer<Value: FixedWidthInteger & UnsignedInteger>() throws -> Value {
        let data = try read(count: Value.bitWidth / 8)
        return data.enumerated().reduce(Value.zero) { value, byte in
            value | (Value(byte.element) << (byte.offset * 8))
        }
    }

    /// Reads the next bytes.
    ///
    /// - Parameter count: The number of bytes to read.
    /// - Returns: The bytes, in order.
    /// - Throws: The reader's error if fewer bytes remain.
    mutating func read(count: Int) throws -> Data {
        guard count >= 0, offset >= 0, count <= bytes.count - offset else { throw error }
        defer { offset += count }
        return Data(bytes[offset..<(offset + count)])
    }
}
