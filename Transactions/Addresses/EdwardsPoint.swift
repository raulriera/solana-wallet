/// Checks whether public address bytes decompress on the Ed25519 curve.
///
/// This is public-data arithmetic for Solana PDA derivation, not secret-key
/// arithmetic or signature validation. Field elements use five 51-bit limbs.
enum EdwardsPoint {
    /// Tests the Edwards equation, accepting the same reduced y coordinates as Dalek.
    ///
    /// - Parameter bytes: A 32-byte compressed point, including its x sign bit.
    /// - Returns: Whether the encoding has a corresponding Edwards point.
    static func isOnCurve(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 32 else { return false }
        var limbs = [UInt128](repeating: 0, count: 5)
        for bit in 0..<255 {
            limbs[bit / 51] |= UInt128((bytes[bit / 8] >> (bit % 8)) & 1) << (bit % 51)
        }
        let y = Field(limbs)
        let square = y * y
        let numerator = square - .one
        let denominator = Field.d * square + .one
        guard denominator != .zero else { return false }
        // n/d is a square exactly when n*d is a square. Euler's criterion avoids
        // computing a square root or an inverse; zero is a valid square as well.
        let product = numerator * denominator
        return product == .zero || product.power() == .one
    }

    /// A canonical residue modulo 2^255 - 19; intermediates fit in UInt128.
    private struct Field: Equatable {
        private static let mask = (UInt128(1) << 51) - 1
        private static let modulus = [mask - 18, mask, mask, mask, mask]
        static let zero = Field([0, 0, 0, 0, 0])
        static let one = Field([1, 0, 0, 0, 0])
        // d = -121665 / 121666 modulo 2^255 - 19.
        static let d = Field([929955233495203, 466365720129213, 1662059464998953,
                              2033849074728123, 1442794654840575])
        private let limbs: [UInt128]

        /// Reduces bounded limbs and subtracts the modulus when needed.
        ///
        /// - Parameter values: Five limbs produced by a field operation.
        init(_ values: [UInt128]) {
            var reduced = values
            for _ in 0..<3 {
                for index in 0..<4 {
                    reduced[index + 1] += reduced[index] >> 51
                    reduced[index] &= Self.mask
                }
                let carry = reduced[4] >> 51
                reduced[4] &= Self.mask
                reduced[0] += carry * 19
            }
            if !reduced.reversed().lexicographicallyPrecedes(Self.modulus.reversed()) {
                var borrow: UInt128 = 0
                for index in 0..<5 {
                    let subtrahend = Self.modulus[index] + borrow
                    borrow = reduced[index] < subtrahend ? 1 : 0
                    reduced[index] = reduced[index] + (borrow << 51) - subtrahend
                }
            }
            limbs = reduced
        }

        /// Adds public field values modulo the curve prime.
        static func + (lhs: Self, rhs: Self) -> Self {
            Self(zip(lhs.limbs, rhs.limbs).map(+))
        }

        /// Subtracts public field values without unsigned underflow.
        static func - (lhs: Self, rhs: Self) -> Self {
            Self((0..<5).map { lhs.limbs[$0] + 2 * modulus[$0] - rhs.limbs[$0] })
        }

        /// Multiplies bounded limbs, folding 2^255 back into 19.
        static func * (lhs: Self, rhs: Self) -> Self {
            var result = [UInt128](repeating: 0, count: 5)
            for left in 0..<5 {
                for right in 0..<5 {
                    let index = left + right
                    result[index % 5] += lhs.limbs[left] * rhs.limbs[right] * (index >= 5 ? 19 : 1)
                }
            }
            return Self(result)
        }

        /// Raises a public value to (p - 1) / 2 for Euler's quadratic-residue test.
        ///
        /// - Returns: Zero, one, or minus one modulo the prime.
        func power() -> Self {
            var result = Self.one
            // (p - 1) / 2 = 2^254 - 10; low byte is 0xf6.
            for bit in stride(from: 253, through: 0, by: -1) {
                result = result * result
                if bit >= 8 || (0xf6 >> bit) & 1 == 1 { result = result * self }
            }
            return result
        }
    }
}
