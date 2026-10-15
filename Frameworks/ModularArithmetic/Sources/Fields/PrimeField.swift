/// A field of integers modulo an odd prime between 2^64 and 2^256.
///
/// Only this module creates a ``Modulus``, so the list of fields is closed and each one is tested.
public protocol PrimeField: Sendable {
    /// The field's prime modulus and the parameters of its Montgomery arithmetic.
    static var modulus: Modulus { get }
}
