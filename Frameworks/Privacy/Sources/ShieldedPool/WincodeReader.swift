import Encoding

/// A reader of the wincode encoding of the shielded-pool program's instruction data.
struct WincodeReader {
    private var reader: ByteReader
    private let error: any Error

    /// Whether every byte has been read.
    var isAtEnd: Bool { reader.isAtEnd }

    /// Creates a reader.
    ///
    /// - Parameters:
    ///   - bytes: The encoded bytes.
    ///   - offset: The position of the first byte to read.
    ///   - error: The error to throw for bytes that don't follow the encoding.
    init(_ bytes: [UInt8], at offset: Int = 0, error: any Error) {
        reader = ByteReader(bytes, at: offset, error: error)
        self.error = error
    }

    /// Reads an integer in its fixed-width little-endian representation.
    ///
    /// - Returns: The integer.
    /// - Throws: The reader's error if the input is truncated.
    mutating func integer<Value: FixedWidthInteger & UnsignedInteger>() throws -> Value {
        try reader.integer()
    }

    /// Reads a fixed-size byte array, which has no length.
    ///
    /// - Parameter count: The number of bytes.
    /// - Returns: The bytes.
    /// - Throws: The reader's error if fewer bytes remain.
    mutating func array(count: Int) throws -> [UInt8] {
        [UInt8](try reader.read(count: count))
    }

    /// Reads past bytes.
    ///
    /// - Parameter count: The number of bytes.
    /// - Throws: The reader's error if fewer bytes remain.
    mutating func skip(_ count: Int) throws {
        _ = try reader.read(count: count)
    }

    /// Reads the one-byte element count of a sequence.
    ///
    /// - Returns: The number of elements that follow.
    /// - Throws: The reader's error if no byte remains.
    mutating func count() throws -> Int {
        Int(try integer() as UInt8)
    }

    /// Reads whether an option is present.
    ///
    /// - Returns: Whether the option's value follows.
    /// - Throws: The reader's error if no byte remains or the byte is neither 0 nor 1.
    mutating func isPresent() throws -> Bool {
        switch try integer() as UInt8 {
        case 0: false
        case 1: true
        default: throw error
        }
    }

    /// Reads past a byte vector: its little-endian 16-bit length and its bytes.
    ///
    /// - Throws: The reader's error if the vector is truncated.
    mutating func skipVector() throws {
        try skip(Int(try integer() as UInt16))
    }
}
