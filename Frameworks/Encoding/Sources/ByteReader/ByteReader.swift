/// A reader of fields from a byte array.
public struct ByteReader {
    private let bytes: [UInt8]
    private let error: any Error
    public private(set) var offset: Int

    /// Whether every byte has been read.
    public var isAtEnd: Bool { offset >= bytes.count }

    /// The next byte, without reading it, or `nil` when none remains.
    var nextByte: UInt8? { bytes.indices.contains(offset) ? bytes[offset] : nil }

    /// Creates a reader.
    ///
    /// - Parameters:
    ///   - bytes: The bytes to read.
    ///   - offset: The position of the first byte to read.
    ///   - error: The error to throw when a read runs past the end of the input.
    public init(_ bytes: [UInt8], at offset: Int = 0, error: any Error) {
        self.bytes = bytes
        self.offset = offset
        self.error = error
    }

    /// Reads an unsigned integer in its fixed-width little-endian representation.
    ///
    /// - Returns: The integer represented by the next bytes.
    /// - Throws: The reader's error if the input is truncated.
    public mutating func integer<Value: FixedWidthInteger & UnsignedInteger>() throws -> Value {
        try read(count: Value.bitWidth / 8).withUnsafeBytes { Value(littleEndian: $0.loadUnaligned(as: Value.self)) }
    }

    /// Reads the next bytes.
    ///
    /// - Parameter count: The number of bytes to read.
    /// - Returns: The bytes, in order, as a slice of the input.
    /// - Throws: The reader's error if fewer bytes remain.
    public mutating func read(count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, offset >= 0, count <= bytes.count - offset else { throw error }
        defer { offset += count }
        return bytes[offset..<(offset + count)]
    }
}
