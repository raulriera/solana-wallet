/// A field of integers modulo an odd prime between 2^64 and 2^256.
public protocol PrimeField: Sendable {
    /// The field's prime modulus and the parameters of its Montgomery arithmetic.
    static var modulus: Modulus { get }
}
