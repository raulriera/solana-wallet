/// A field of integers modulo an odd prime between 2^64 and 2^256.
public protocol PrimeField: Sendable {
    static var modulus: Modulus { get }
}
