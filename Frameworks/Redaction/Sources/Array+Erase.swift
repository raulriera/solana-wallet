extension [UInt8] {
    /// Overwrites every byte with zero.
    public mutating func erase() {
        withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
    }
}
