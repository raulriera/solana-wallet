/// The self-shrinking Grain LFSR that generates Poseidon's parameters for the BN254 scalar field.
struct Grain {
    /// The bit length of the BN254 scalar field's modulus and of each drawn value.
    private static let fieldBits = 254

    /// The register, with s₀ in bit 79 and s₇₉ in bit 0.
    private var register: UInt128

    /// Creates a generator seeded for one Poseidon instance.
    ///
    /// - Parameters:
    ///   - width: The number of state elements, t.
    ///   - fullRounds: The number of full rounds.
    ///   - partialRounds: The number of partial rounds.
    init(width: Int, fullRounds: Int, partialRounds: Int) {
        register = (UInt128(1) << 78)
            | (UInt128(Self.fieldBits) << 62)
            | (UInt128(width) << 50)
            | (UInt128(fullRounds) << 40)
            | (UInt128(partialRounds) << 30)
            | ((UInt128(1) << 30) - 1)
        for _ in 0..<160 {
            clock()
        }
    }

    /// Draws 254 bits, most significant first.
    ///
    /// - Returns: The bits as a 32-byte big-endian value below 2^254.
    mutating func nextValue() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32)
        for position in (256 - Self.fieldBits)..<256 {
            bytes[position / 8] |= nextBit() << (7 - position % 8)
        }
        return bytes
    }

    /// Reads bit pairs until the first bit of a pair is one.
    ///
    /// - Returns: The second bit of that pair.
    private mutating func nextBit() -> UInt8 {
        while clock() == 0 {
            clock()
        }
        return UInt8(clock())
    }

    /// Shifts the register by one bit.
    ///
    /// - Returns: The new bit s₇₉.
    @discardableResult
    private mutating func clock() -> UInt128 {
        let bit = ((register >> 79) ^ (register >> 66) ^ (register >> 56)
            ^ (register >> 41) ^ (register >> 28) ^ (register >> 17)) & 1
        register = ((register << 1) | bit) & ((UInt128(1) << 80) - 1)
        return bit
    }
}
