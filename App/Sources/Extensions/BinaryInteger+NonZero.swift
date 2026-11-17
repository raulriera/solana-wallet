nonisolated extension BinaryInteger {
    /// The value, or `nil` when it's zero.
    var nonZero: Self? { self == 0 ? nil : self }
}
