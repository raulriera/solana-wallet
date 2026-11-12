import Encoding

/// A writer of the wincode encoding of the shielded-pool program's instruction data.
struct WincodeWriter {
    /// A value that the encoding can't represent.
    enum ValidationError: Error, Equatable {
        case lengthOverflow
    }

    private(set) var bytes: [UInt8] = []

    /// Creates an empty writer.
    init() {}

    /// Appends an integer in its fixed-width little-endian representation.
    ///
    /// - Parameter value: The integer.
    mutating func append(_ value: some FixedWidthInteger) {
        bytes.append(littleEndian: value)
    }

    /// Appends a fixed-size byte array without a length.
    ///
    /// - Parameter array: The bytes.
    mutating func append(array: [UInt8]) {
        bytes += array
    }

    /// Appends the one-byte element count of a sequence.
    ///
    /// - Parameter count: The number of elements that follow.
    /// - Throws: ``ValidationError/lengthOverflow`` for more than 255 elements.
    mutating func appendCount(_ count: Int) throws {
        guard let count = UInt8(exactly: count) else { throw ValidationError.lengthOverflow }
        append(count)
    }

    /// Appends an absent option.
    mutating func appendNone() {
        append(UInt8(0))
    }

    /// Appends a present option that holds a byte vector: the byte 1, the vector's little-endian
    /// 16-bit length, and its bytes.
    ///
    /// - Parameter vector: The bytes.
    /// - Throws: ``ValidationError/lengthOverflow`` for more than 65,535 bytes.
    mutating func appendSome(vector: [UInt8]) throws {
        guard let length = UInt16(exactly: vector.count) else { throw ValidationError.lengthOverflow }
        append(UInt8(1))
        append(length)
        bytes += vector
    }
}
