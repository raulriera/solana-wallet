extension [UInt8] {
    func replacingSubrange(_ range: Range<Int>, with bytes: [UInt8]) -> [UInt8] {
        var copy = self
        copy.replaceSubrange(range, with: bytes)
        return copy
    }
}
