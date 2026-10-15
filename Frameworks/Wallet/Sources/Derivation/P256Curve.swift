import ModularArithmetic

/// SLIP-0010's NIST P-256 rules, which name the curve nist256p1.
///
/// A private key is a scalar from 1 to n - 1, where n is the order of the curve's base point.
struct P256Curve: DerivationCurve {
    /// A scalar modulo n.
    private typealias Scalar = FieldElement<P256ScalarField>

    /// The master HMAC key that SLIP-0010 assigns to P-256.
    var label: String { "Nist256p1 seed" }

    /// Accepts a master candidate from 1 to n - 1, or adds a child candidate below n to its parent.
    ///
    /// SLIP-0010 hashes again when a master candidate is 0 or at least n, or when a child candidate
    /// is at least n or its sum with the parent is 0 modulo n.
    ///
    /// - Parameters:
    ///   - candidate: The left 32 bytes of the output, I_L, in big-endian order.
    ///   - parent: The parent's private key, a scalar this rule accepted, or `nil` for the master key.
    /// - Returns: The master candidate unchanged, the child key (I_L + parent) mod n in 32 big-endian
    ///   bytes, or `nil` when SLIP-0010 requires another hash.
    func privateKey(candidate: [UInt8], parent: [UInt8]?) -> [UInt8]? {
        guard let tweak = Scalar(bigEndianBytes: candidate) else { return nil }
        guard let parent else { return tweak == .zero ? nil : candidate }
        // The parent is already below n, so reducing it leaves it unchanged.
        let child = tweak + Scalar(reducing: parent)
        return child == .zero ? nil : child.bigEndianBytes
    }
}

extension DerivationCurve where Self == P256Curve {
    /// SLIP-0010's NIST P-256 rules, which Solana Rings viewing keys use.
    static var p256: Self { P256Curve() }
}
