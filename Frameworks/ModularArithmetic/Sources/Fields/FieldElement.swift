/// An element of a prime field, stored as four 64-bit limbs in Montgomery form.
///
/// Operations have no branches or memory indices that depend on values, and equality compares
/// every limb. Descriptions and reflection omit the value; ``bigEndianBytes`` exposes it
/// explicitly. Swift doesn't guarantee constant-time code or memory erasure.
public struct FieldElement<Field: PrimeField>: Sendable, Equatable, AdditiveArithmetic,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The value times R = 2^256, modulo the field's modulus.
    private let montgomery: Limbs

    /// The additive identity.
    public static var zero: Self { Self(montgomery: .zero) }

    /// The multiplicative identity.
    public static var one: Self { Self(montgomery: Field.modulus.one) }

    /// The canonical encoding: 32 big-endian bytes below the modulus.
    public var bigEndianBytes: [UInt8] {
        Field.modulus.canonical(montgomery).bigEndianBytes
    }

    /// A description that omits the value.
    public var description: String { "FieldElement" }

    /// A debugging description that omits the value.
    public var debugDescription: String { description }

    /// A reflection view that omits the value.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates an element from its Montgomery form.
    ///
    /// - Parameter montgomery: The value times R, below the modulus.
    private init(montgomery: Limbs) {
        self.montgomery = montgomery
    }

    /// Creates an element from an integer, which is below every field's modulus.
    ///
    /// - Parameter value: The integer value.
    public init(_ value: UInt64) {
        self.init(montgomery: Field.modulus.montgomery(Limbs(value, 0, 0, 0)))
    }

    /// Decodes a canonical element.
    ///
    /// Only whether the input is canonical affects the control flow.
    ///
    /// - Parameter bytes: Exactly 32 big-endian bytes.
    /// - Returns: The element, or `nil` if `bytes` doesn't contain 32 bytes or encodes a value at
    ///   or above the modulus.
    public init?(bigEndianBytes bytes: [UInt8]) {
        guard bytes.count == 32 else { return nil }
        let modulus = Field.modulus
        let value = Limbs(bigEndianBytes: bytes)
        // Subtracting the modulus borrows exactly when the value is below it.
        guard value.subtracting(modulus.limbs).borrow == 1 else { return nil }
        self.init(montgomery: modulus.montgomery(value))
    }

    /// Reduces any 256-bit value modulo the field's modulus.
    ///
    /// - Parameter bigEndianBytes: Exactly 32 big-endian bytes, which may encode a value at or
    ///   above the modulus.
    /// - Precondition: `bigEndianBytes` contains exactly 32 bytes.
    public init(reducing bigEndianBytes: [UInt8]) {
        self.init(montgomery: Field.modulus.montgomery(Limbs(bigEndianBytes: bigEndianBytes)))
    }

    /// Compares two elements in every limb, without stopping at the first difference.
    ///
    /// - Parameters:
    ///   - lhs: An element.
    ///   - rhs: Another element.
    /// - Returns: Whether the elements are equal.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.montgomery == rhs.montgomery
    }

    /// Adds two elements modulo the field's modulus.
    ///
    /// - Parameters:
    ///   - lhs: An element.
    ///   - rhs: The element to add.
    /// - Returns: The sum.
    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(montgomery: lhs.montgomery.adding(rhs.montgomery, modulo: Field.modulus.limbs))
    }

    /// Subtracts one element from another modulo the field's modulus.
    ///
    /// - Parameters:
    ///   - lhs: An element.
    ///   - rhs: The element to subtract.
    /// - Returns: The difference.
    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(montgomery: lhs.montgomery.subtracting(rhs.montgomery, modulo: Field.modulus.limbs))
    }

    /// Negates an element modulo the field's modulus.
    ///
    /// - Parameter operand: An element.
    /// - Returns: The element that adds to `operand` to give zero.
    public static prefix func - (operand: Self) -> Self {
        zero - operand
    }

    /// Multiplies two elements modulo the field's modulus.
    ///
    /// - Parameters:
    ///   - lhs: An element.
    ///   - rhs: The element to multiply by.
    /// - Returns: The product.
    public static func * (lhs: Self, rhs: Self) -> Self {
        Self(montgomery: Field.modulus.multiply(lhs.montgomery, rhs.montgomery))
    }

    /// Computes the multiplicative inverse by Fermat's little theorem.
    ///
    /// Raises the element to the public exponent m - 2, so the sequence of operations doesn't
    /// depend on the element.
    ///
    /// - Returns: The element that multiplies with this one to give one, or zero for zero.
    public func inverse() -> Self {
        let modulus = Field.modulus
        return Self(montgomery: modulus.power(montgomery, modulus.inverseExponent))
    }
}
