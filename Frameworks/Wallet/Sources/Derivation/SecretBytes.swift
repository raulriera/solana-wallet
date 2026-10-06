extension [UInt8] {
    /// Overwrites every byte with zero before the buffer is released.
    ///
    /// This reduces secret residue in memory on a best-effort basis. Swift may have
    /// copied the bytes elsewhere, and those copies are not affected.
    mutating func erase() {
        withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
    }
}
