extension [UInt8] {
    /// Appends an integer's fixed-width little-endian bytes.
    ///
    /// - Parameter value: The integer to append.
    mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Reads a fixed-width little-endian integer.
    ///
    /// - Parameter offset: The index of the integer's first byte.
    /// - Returns: The integer whose bytes start at `offset`.
    func littleEndian<Integer: FixedWidthInteger>(at offset: Int) -> Integer {
        self[offset..<offset + Integer.bitWidth / 8].withUnsafeBytes { Integer(littleEndian: $0.loadUnaligned(as: Integer.self)) }
    }
}
