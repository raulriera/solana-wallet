/// A writer of the wincode encoding that the shielded-pool program reads its instruction data in.
///
/// The encoding follows zolana's `deposit` and `transact` instruction data: integers are fixed-width
/// and little-endian; fixed-size byte arrays are written raw; enum variants and element counts are
/// one byte; byte vectors carry a little-endian 16-bit length; and an option is the byte 0 for none,
/// or the byte 1 followed by its value.
struct WincodeWriter {
    /// A value that the encoding can't represent.
    enum ValidationError: Error, Equatable {
        /// A sequence has more elements than its length prefix can count.
        case lengthOverflow
    }

    /// The bytes written so far.
    private(set) var bytes: [UInt8] = []

    /// Creates an empty writer.
    init() {}

    /// Appends an integer in its fixed-width little-endian representation, such as an instruction
    /// tag, an enum variant, or an amount.
    ///
    /// - Parameter value: The integer.
    mutating func append(_ value: some FixedWidthInteger) {
        bytes.appendLittleEndian(value)
    }

    /// Appends a fixed-size byte array, such as a hash or an address, without a length.
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
