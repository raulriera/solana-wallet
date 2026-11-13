extension [UInt8] {
    /// Reads a fixed-width little-endian integer.
    ///
    /// - Parameter offset: The index of the integer's first byte.
    /// - Returns: The integer whose bytes start at `offset`.
    func littleEndian<Integer: FixedWidthInteger>(at offset: Int) -> Integer {
        self[offset..<offset + Integer.bitWidth / 8].withUnsafeBytes { Integer(littleEndian: $0.loadUnaligned(as: Integer.self)) }
    }
}
