import Foundation

/// Reads bounded byte ranges without unaligned loads or unchecked offsets.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var offset = 0

    /// Creates a reader with zero-based indices, including for sliced Foundation data.
    ///
    /// - Parameter data: The size-bounded input owned by one decoding operation.
    init(_ data: Data) {
        bytes = Array(data)
    }

    /// Reads an unsigned integer in its fixed-width little-endian representation.
    ///
    /// - Returns: The integer represented by the next bytes.
    /// - Throws: ``ValidationError/invalidTransaction`` if the input is truncated.
    mutating func integer<Value: FixedWidthInteger & UnsignedInteger>() throws -> Value {
        let data = try read(count: Value.bitWidth / 8)
        return data.enumerated().reduce(Value.zero) { value, byte in
            value | (Value(byte.element) << (byte.offset * 8))
        }
    }

    /// Reads a byte range only if the complete range remains in the input.
    ///
    /// - Parameter count: The nonnegative number of bytes to consume.
    /// - Returns: The requested bytes in their original order.
    /// - Throws: ``ValidationError/invalidTransaction`` if the range is unavailable.
    mutating func read(count: Int) throws -> Data {
        guard count >= 0, count <= bytes.count - offset else {
            throw ValidationError.invalidTransaction
        }
        defer { offset += count }
        return Data(bytes[offset..<(offset + count)])
    }
}
