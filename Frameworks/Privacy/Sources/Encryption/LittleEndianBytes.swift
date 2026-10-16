extension [UInt8] {
    /// Appends an integer in its fixed-width little-endian representation, as Solana Rings
    /// payloads encode integers.
    ///
    /// - Parameter value: The integer to append, without padding or a length prefix.
    mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Reads a fixed-width little-endian integer, as Solana Rings payloads encode integers.
    ///
    /// - Parameter offset: The index of the integer's first byte.
    /// - Returns: The integer whose bytes start at `offset`.
    /// - Precondition: The array holds the integer's bytes from `offset`.
    func littleEndian<Integer: FixedWidthInteger>(at offset: Int) -> Integer {
        self[offset..<offset + Integer.bitWidth / 8].withUnsafeBytes { Integer(littleEndian: $0.loadUnaligned(as: Integer.self)) }
    }
}
