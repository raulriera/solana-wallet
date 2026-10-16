/// A deterministic random number generator, SplitMix64, so plans with random values repeat.
///
/// It isn't cryptographically secure; only tests use it.
struct SeededGenerator: RandomNumberGenerator {
    /// The generator's state.
    private var state: UInt64

    /// Creates a generator.
    ///
    /// - Parameter seed: The first state.
    init(seed: UInt64) {
        state = seed
    }

    /// Returns the next value and advances the state.
    ///
    /// - Returns: A pseudo-random 64-bit value.
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
        value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
        return value ^ (value >> 31)
    }
}
