/// An element of a prime field, stored as four 64-bit limbs in Montgomery form.
public struct FieldElement<Field: PrimeField>: Sendable, Equatable, AdditiveArithmetic,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The value times R = 2^256, modulo the field's modulus.
    private let montgomery: Limbs

    public static var zero: Self { Self(montgomery: .zero) }

    public static var one: Self { Self(montgomery: Field.modulus.one) }

    /// The canonical value as 32 big-endian bytes.
    public var bigEndianBytes: [UInt8] {
        Field.modulus.canonical(montgomery).bigEndianBytes
    }

    public var description: String { "FieldElement" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates an element from its Montgomery form.
    ///
    /// - Parameter montgomery: The value times R, below the modulus.
    private init(montgomery: Limbs) {
        self.montgomery = montgomery
    }

    /// Creates an element from an integer.
    ///
    /// - Parameter value: The integer value.
    public init(_ value: UInt64) {
        self.init(montgomery: Field.modulus.montgomery(Limbs(value, 0, 0, 0)))
    }

    /// Creates an element from its canonical encoding, or returns `nil` if the bytes aren't canonical.
    ///
    /// - Parameter bytes: 32 big-endian bytes that encode a value below the modulus.
    public init?(bigEndianBytes bytes: [UInt8]) {
        guard bytes.count == 32 else { return nil }
        let modulus = Field.modulus
        let value = Limbs(bigEndianBytes: bytes)
        guard value.subtracting(modulus.limbs).borrow == 1 else { return nil }
        self.init(montgomery: modulus.montgomery(value))
    }

    /// Creates an element by reducing a 256-bit value modulo the field's modulus.
    ///
    /// - Parameter bigEndianBytes: 32 big-endian bytes that encode any value.
    public init(reducing bigEndianBytes: [UInt8]) {
        self.init(montgomery: Field.modulus.montgomery(Limbs(bigEndianBytes: bigEndianBytes)))
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.montgomery == rhs.montgomery
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(montgomery: lhs.montgomery.adding(rhs.montgomery, modulo: Field.modulus.limbs))
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(montgomery: lhs.montgomery.subtracting(rhs.montgomery, modulo: Field.modulus.limbs))
    }

    /// Negates an element modulo the field's modulus.
    ///
    /// - Parameter operand: The element to negate.
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

    /// Returns the multiplicative inverse.
    ///
    /// - Returns: The element that multiplies with this one to give one, or zero for zero.
    public func inverse() -> Self {
        let modulus = Field.modulus
        return Self(montgomery: modulus.power(montgomery, modulus.inverseExponent))
    }
}
