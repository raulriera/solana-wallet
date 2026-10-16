extension [UInt8] {
    /// Returns a copy with one range of bytes replaced, such as a fixture with a malformed field.
    ///
    /// - Parameters:
    ///   - range: The positions to replace.
    ///   - bytes: The replacement bytes, which may have another length.
    /// - Returns: The edited copy.
    func replacingSubrange(_ range: Range<Int>, with bytes: [UInt8]) -> [UInt8] {
        var copy = self
        copy.replaceSubrange(range, with: bytes)
        return copy
    }
}
