/// A 256-bit value as four little-endian 64-bit limbs.
///
/// Carries and borrows come from 128-bit arithmetic and choices from masks, so no branch or
/// memory index depends on a value. The arithmetic helpers are `@inline(always)`; Swift doesn't
/// guarantee the generated instructions.
struct Limbs: Sendable, Equatable {
    /// Bits 0 to 63.
    let limb0: UInt64
    /// Bits 64 to 127.
    let limb1: UInt64
    /// Bits 128 to 191.
    let limb2: UInt64
    /// Bits 192 to 255.
    let limb3: UInt64

    /// The value zero.
    @inline(always) static var zero: Self { Self(0, 0, 0, 0) }

    /// The value as 32 big-endian bytes.
    var bigEndianBytes: [UInt8] {
        [limb3, limb2, limb1, limb0].flatMap { limb in
            stride(from: 56, through: 0, by: -8).map { UInt8(truncatingIfNeeded: limb >> $0) }
        }
    }

    /// Creates a value from its limbs, least significant first.
    ///
    /// - Parameters:
    ///   - limb0: Bits 0 to 63.
    ///   - limb1: Bits 64 to 127.
    ///   - limb2: Bits 128 to 191.
    ///   - limb3: Bits 192 to 255.
    @inline(always) init(_ limb0: UInt64, _ limb1: UInt64, _ limb2: UInt64, _ limb3: UInt64) {
        self.limb0 = limb0
        self.limb1 = limb1
        self.limb2 = limb2
        self.limb3 = limb3
    }

    /// Reads a value from big-endian bytes.
    ///
    /// - Parameter bytes: Exactly 32 bytes, most significant first.
    /// - Precondition: `bytes` contains exactly 32 bytes.
    init(bigEndianBytes bytes: [UInt8]) {
        precondition(bytes.count == 32, "A 256-bit value needs exactly 32 bytes.")
        let limbs = stride(from: 24, through: 0, by: -8).map { start in
            bytes[start..<start + 8].reduce(UInt64.zero) { $0 << 8 | UInt64($1) }
        }
        self.init(limbs[0], limbs[1], limbs[2], limbs[3])
    }

    /// Compares every limb without stopping at the first difference.
    ///
    /// - Parameters:
    ///   - lhs: A value.
    ///   - rhs: Another value.
    /// - Returns: Whether the values are equal.
    static func == (lhs: Self, rhs: Self) -> Bool {
        ((lhs.limb0 ^ rhs.limb0) | (lhs.limb1 ^ rhs.limb1) | (lhs.limb2 ^ rhs.limb2) | (lhs.limb3 ^ rhs.limb3)) == 0
    }

    /// Chooses one of two values with a mask instead of a branch.
    ///
    /// - Parameters:
    ///   - condition: One to choose `first`, or zero to choose `second`.
    ///   - first: The value for a condition of one.
    ///   - second: The value for a condition of zero.
    /// - Returns: The chosen value.
    @inline(always) static func select(_ condition: UInt64, _ first: Self, _ second: Self) -> Self {
        let mask = 0 &- condition
        return Self(
            (first.limb0 & mask) | (second.limb0 & ~mask),
            (first.limb1 & mask) | (second.limb1 & ~mask),
            (first.limb2 & mask) | (second.limb2 & ~mask),
            (first.limb3 & mask) | (second.limb3 & ~mask)
        )
    }

    /// Adds another value modulo 2^256.
    ///
    /// - Parameter other: The value to add.
    /// - Returns: The low 256 bits of the sum, and one if the sum reached 2^256 or zero otherwise.
    @inline(always) func adding(_ other: Self) -> (sum: Self, carry: UInt64) {
        let (sum0, carry0) = limb0.adding(other.limb0, carry: 0)
        let (sum1, carry1) = limb1.adding(other.limb1, carry: carry0)
        let (sum2, carry2) = limb2.adding(other.limb2, carry: carry1)
        let (sum3, carry3) = limb3.adding(other.limb3, carry: carry2)
        return (Self(sum0, sum1, sum2, sum3), carry3)
    }

    /// Subtracts another value modulo 2^256.
    ///
    /// - Parameter other: The value to subtract.
    /// - Returns: The difference modulo 2^256, and one if `other` exceeds this value or zero otherwise.
    @inline(always) func subtracting(_ other: Self) -> (difference: Self, borrow: UInt64) {
        let (difference0, borrow0) = limb0.subtracting(other.limb0, borrow: 0)
        let (difference1, borrow1) = limb1.subtracting(other.limb1, borrow: borrow0)
        let (difference2, borrow2) = limb2.subtracting(other.limb2, borrow: borrow1)
        let (difference3, borrow3) = limb3.subtracting(other.limb3, borrow: borrow2)
        return (Self(difference0, difference1, difference2, difference3), borrow3)
    }

    /// Subtracts the modulus once when this value, with a carry above 2^256, reaches it.
    ///
    /// - Parameters:
    ///   - carry: Zero or one, the bit above the four limbs.
    ///   - modulus: The modulus; the value with its carry must be below twice the modulus.
    /// - Returns: The value modulo `modulus`.
    @inline(always) func reduced(carry: UInt64, modulo modulus: Self) -> Self {
        let (difference, borrow) = subtracting(modulus)
        // Continuing the subtraction through the carry limb leaves a final borrow exactly when
        // the value is below the modulus.
        let (_, isBelowModulus) = carry.subtracting(0, borrow: borrow)
        return .select(isBelowModulus, self, difference)
    }

    /// Adds another value modulo an odd modulus.
    ///
    /// - Parameters:
    ///   - other: A value below `modulus`.
    ///   - modulus: The modulus; this value must also be below it.
    /// - Returns: The sum modulo `modulus`.
    @inline(always) func adding(_ other: Self, modulo modulus: Self) -> Self {
        let (sum, carry) = adding(other)
        return sum.reduced(carry: carry, modulo: modulus)
    }

    /// Subtracts another value modulo an odd modulus.
    ///
    /// - Parameters:
    ///   - other: A value below `modulus`.
    ///   - modulus: The modulus; this value must also be below it.
    /// - Returns: The difference modulo `modulus`.
    @inline(always) func subtracting(_ other: Self, modulo modulus: Self) -> Self {
        let (difference, borrow) = subtracting(other)
        // A borrow wrapped the difference past 2^256; adding the modulus wraps it back below it.
        return .select(borrow, difference.adding(modulus).sum, difference)
    }
}

extension UInt64 {
    /// Adds another limb and a carry.
    ///
    /// - Parameters:
    ///   - other: The limb to add.
    ///   - carry: The carry from the previous limb.
    /// - Returns: The low 64 bits of the sum and the carry into the next limb.
    @inline(always) func adding(_ other: UInt64, carry: UInt64) -> (UInt64, carry: UInt64) {
        let sum = UInt128(self) &+ UInt128(other) &+ UInt128(carry)
        return (UInt64(truncatingIfNeeded: sum), UInt64(truncatingIfNeeded: sum &>> 64))
    }

    /// Subtracts another limb and a borrow.
    ///
    /// - Parameters:
    ///   - other: The limb to subtract.
    ///   - borrow: Zero or one, the borrow from the previous limb.
    /// - Returns: The difference modulo 2^64, and one if the subtraction wrapped or zero otherwise.
    @inline(always) func subtracting(_ other: UInt64, borrow: UInt64) -> (UInt64, borrow: UInt64) {
        // A negative 128-bit difference wraps to a value with its top bit set.
        let difference = UInt128(self) &- UInt128(other) &- UInt128(borrow)
        return (UInt64(truncatingIfNeeded: difference), UInt64(truncatingIfNeeded: difference &>> 127))
    }

    /// Multiplies by another limb and adds two limbs, which can't overflow 128 bits.
    ///
    /// - Parameters:
    ///   - other: The limb to multiply by.
    ///   - addend: A limb to add to the product.
    ///   - carry: The carry from the previous limb.
    /// - Returns: The low 64 bits of the result and the carry into the next limb.
    @inline(always) func multiplied(by other: UInt64, adding addend: UInt64, carry: UInt64) -> (UInt64, carry: UInt64) {
        let result = UInt128(self) &* UInt128(other) &+ UInt128(addend) &+ UInt128(carry)
        return (UInt64(truncatingIfNeeded: result), UInt64(truncatingIfNeeded: result &>> 64))
    }
}
