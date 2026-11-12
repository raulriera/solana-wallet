extension RangeReplaceableCollection<UInt8> {
    /// Appends an integer's fixed-width little-endian bytes.
    ///
    /// - Parameter value: The integer to append.
    public mutating func append(littleEndian value: some FixedWidthInteger) {
        withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Appends an integer's fixed-width big-endian bytes.
    ///
    /// - Parameter value: The integer to append.
    public mutating func append(bigEndian value: some FixedWidthInteger) {
        withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
