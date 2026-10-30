/// A 256-bit value as four little-endian 64-bit limbs.
struct Limbs: Sendable, Equatable {
    /// Bits 0 to 63.
    let limb0: UInt64
    /// Bits 64 to 127.
    let limb1: UInt64
    /// Bits 128 to 191.
    let limb2: UInt64
    /// Bits 192 to 255.
    let limb3: UInt64

    @inline(always) static var zero: Self { Self(0, 0, 0, 0) }

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

    /// Creates a value from big-endian bytes.
    ///
    /// - Parameter bytes: Exactly 32 bytes, most significant first.
    init(bigEndianBytes bytes: [UInt8]) {
        precondition(bytes.count == 32, "A 256-bit value needs exactly 32 bytes.")
        let limbs = stride(from: 24, through: 0, by: -8).map { start in
            bytes[start..<start + 8].reduce(UInt64.zero) { $0 << 8 | UInt64($1) }
        }
        self.init(limbs[0], limbs[1], limbs[2], limbs[3])
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        ((lhs.limb0 ^ rhs.limb0) | (lhs.limb1 ^ rhs.limb1) | (lhs.limb2 ^ rhs.limb2) | (lhs.limb3 ^ rhs.limb3)) == 0
    }

    /// Chooses one of two values without branching.
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
    /// - Returns: The sum modulo 2^256 and its carry, zero or one.
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
    /// - Returns: The difference modulo 2^256 and its borrow, zero or one.
    @inline(always) func subtracting(_ other: Self) -> (difference: Self, borrow: UInt64) {
        let (difference0, borrow0) = limb0.subtracting(other.limb0, borrow: 0)
        let (difference1, borrow1) = limb1.subtracting(other.limb1, borrow: borrow0)
        let (difference2, borrow2) = limb2.subtracting(other.limb2, borrow: borrow1)
        let (difference3, borrow3) = limb3.subtracting(other.limb3, borrow: borrow2)
        return (Self(difference0, difference1, difference2, difference3), borrow3)
    }

    /// Reduces this value and a carry above 2^256 by subtracting a modulus at most once.
    ///
    /// - Parameters:
    ///   - carry: The bit above the four limbs, zero or one.
    ///   - modulus: The modulus, more than half the value with its carry.
    /// - Returns: The value modulo `modulus`.
    @inline(always) func reduced(carry: UInt64, modulo modulus: Self) -> Self {
        let (difference, borrow) = subtracting(modulus)
        let (_, isBelowModulus) = carry.subtracting(0, borrow: borrow)
        return .select(isBelowModulus, self, difference)
    }

    /// Adds another value modulo an odd modulus.
    ///
    /// - Parameters:
    ///   - other: A value below `modulus`.
    ///   - modulus: The modulus, greater than this value.
    /// - Returns: The sum modulo `modulus`.
    @inline(always) func adding(_ other: Self, modulo modulus: Self) -> Self {
        let (sum, carry) = adding(other)
        return sum.reduced(carry: carry, modulo: modulus)
    }

    /// Subtracts another value modulo an odd modulus.
    ///
    /// - Parameters:
    ///   - other: A value below `modulus`.
    ///   - modulus: The modulus, greater than this value.
    /// - Returns: The difference modulo `modulus`.
    @inline(always) func subtracting(_ other: Self, modulo modulus: Self) -> Self {
        let (difference, borrow) = subtracting(other)
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
    /// - Returns: The difference modulo 2^64 and the borrow into the next limb.
    @inline(always) func subtracting(_ other: UInt64, borrow: UInt64) -> (UInt64, borrow: UInt64) {
        let difference = UInt128(self) &- UInt128(other) &- UInt128(borrow)
        return (UInt64(truncatingIfNeeded: difference), UInt64(truncatingIfNeeded: difference &>> 127))
    }

    /// Multiplies by another limb and adds two limbs.
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
