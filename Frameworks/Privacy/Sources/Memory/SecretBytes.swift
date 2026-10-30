extension [UInt8] {
    /// Overwrites every byte with zero.
    mutating func erase() {
        withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
    }
}
