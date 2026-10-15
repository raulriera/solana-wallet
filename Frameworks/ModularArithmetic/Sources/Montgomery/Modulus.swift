/// An odd prime modulus between 2^64 and 2^256, with the parameters of its Montgomery arithmetic.
///
/// Field elements use Montgomery form with R = 2^256. The parameters are computed once from the
/// public modulus. Only this module creates moduli, so the list of fields stays closed and tested.
public struct Modulus: Sendable {
    /// The modulus m.
    let limbs: Limbs
    /// -m⁻¹ mod 2^64, the factor that clears the lowest limb in each reduction step.
    let negatedInverse: UInt64
    /// R mod m, the Montgomery form of one.
    let one: Limbs
    /// R² mod m, which converts a value into Montgomery form.
    let rSquared: Limbs
    /// m - 2, the exponent of an inverse by Fermat's little theorem.
    let inverseExponent: Limbs

    /// Computes the Montgomery parameters of an odd modulus between 2^64 and 2^256.
    ///
    /// - Parameters:
    ///   - limb0: Bits 0 to 63 of the modulus.
    ///   - limb1: Bits 64 to 127 of the modulus.
    ///   - limb2: Bits 128 to 191 of the modulus.
    ///   - limb3: Bits 192 to 255 of the modulus.
    init(_ limb0: UInt64, _ limb1: UInt64, _ limb2: UInt64, _ limb3: UInt64) {
        let limbs = Limbs(limb0, limb1, limb2, limb3)
        // An odd number is its own inverse modulo 2^3, and each Newton step doubles the
        // correct low bits, so five steps give 96 ≥ 64 bits of m⁻¹ mod 2^64.
        var inverse = limb0
        for _ in 0..<5 {
            inverse = inverse &* (2 &- limb0 &* inverse)
        }
        // Doubling one 256 times gives R mod m; 256 more doublings give R² mod m.
        var power = Limbs(1, 0, 0, 0)
        for _ in 0..<256 {
            power = power.adding(power, modulo: limbs)
        }
        let one = power
        for _ in 0..<256 {
            power = power.adding(power, modulo: limbs)
        }
        self.limbs = limbs
        negatedInverse = 0 &- inverse
        self.one = one
        rSquared = power
        inverseExponent = limbs.subtracting(Limbs(2, 0, 0, 0)).difference
    }

    /// Converts a value into Montgomery form, reducing it modulo m.
    ///
    /// - Parameter value: Any value below 2^256.
    /// - Returns: `value × R mod m`.
    func montgomery(_ value: Limbs) -> Limbs {
        multiply(value, rSquared)
    }

    /// Converts a value out of Montgomery form.
    ///
    /// - Parameter value: A value in Montgomery form, below m.
    /// - Returns: `value × R⁻¹ mod m`, the canonical residue.
    func canonical(_ value: Limbs) -> Limbs {
        multiply(value, Limbs(1, 0, 0, 0))
    }

    /// Multiplies two values with Montgomery reduction.
    ///
    /// Coarsely integrated operand scanning (CIOS) adds one row of `a × b` and one row of a
    /// multiple of m for each limb of `b`, then drops the cleared lowest limb. The running sum
    /// keeps two limbs above the four limbs of `a`, so the result is correct for any odd modulus
    /// below 2^256, including moduli above 2^255.
    ///
    /// - Parameters:
    ///   - a: Any value below 2^256.
    ///   - b: A value below m.
    /// - Returns: `a × b × R⁻¹ mod m`, below m.
    func multiply(_ a: Limbs, _ b: Limbs) -> Limbs {
        var sum = (low: Limbs.zero, high: UInt64.zero)
        sum = scan(sum, a, b.limb0)
        sum = scan(sum, a, b.limb1)
        sum = scan(sum, a, b.limb2)
        sum = scan(sum, a, b.limb3)
        // The sum is now below 2m, so one conditional subtraction reduces it.
        return sum.low.reduced(carry: sum.high, modulo: limbs)
    }

    /// Raises a value in Montgomery form to a public exponent by square-and-multiply.
    ///
    /// The sequence of multiplications depends only on the exponent's bits, never on the base.
    ///
    /// - Parameters:
    ///   - base: A value in Montgomery form, below m.
    ///   - exponent: A public exponent.
    /// - Returns: `base` raised to `exponent`, in Montgomery form.
    func power(_ base: Limbs, _ exponent: Limbs) -> Limbs {
        var result = one
        for limb in [exponent.limb3, exponent.limb2, exponent.limb1, exponent.limb0] {
            for shift in stride(from: 63, through: 0, by: -1) {
                result = multiply(result, result)
                if (limb >> shift) & 1 == 1 {
                    result = multiply(result, base)
                }
            }
        }
        return result
    }

    /// Performs one CIOS step: adds `a × word` to the running sum, then adds the multiple of m
    /// that clears the sum's lowest limb, and shifts the sum down by one limb.
    ///
    /// - Parameters:
    ///   - sum: The running sum, below `a + m`, as four limbs and a fifth limb of zero or one.
    ///   - a: The multiplicand.
    ///   - word: The next limb of the multiplier.
    /// - Returns: The next running sum, again below `a + m`.
    @inline(always) private func scan(_ sum: (low: Limbs, high: UInt64), _ a: Limbs, _ word: UInt64) -> (low: Limbs, high: UInt64) {
        let (t0, c0) = a.limb0.multiplied(by: word, adding: sum.low.limb0, carry: 0)
        let (t1, c1) = a.limb1.multiplied(by: word, adding: sum.low.limb1, carry: c0)
        let (t2, c2) = a.limb2.multiplied(by: word, adding: sum.low.limb2, carry: c1)
        let (t3, c3) = a.limb3.multiplied(by: word, adding: sum.low.limb3, carry: c2)
        let (t4, t5) = sum.high.adding(c3, carry: 0)

        let factor = t0 &* negatedInverse
        // The lowest limb of t0 + factor × m0 is zero by the choice of factor; only its carry remains.
        let (_, d0) = limbs.limb0.multiplied(by: factor, adding: t0, carry: 0)
        let (u0, d1) = limbs.limb1.multiplied(by: factor, adding: t1, carry: d0)
        let (u1, d2) = limbs.limb2.multiplied(by: factor, adding: t2, carry: d1)
        let (u2, d3) = limbs.limb3.multiplied(by: factor, adding: t3, carry: d2)
        let (u3, d4) = t4.adding(d3, carry: 0)
        return (Limbs(u0, u1, u2, u3), t5 &+ d4)
    }
}
