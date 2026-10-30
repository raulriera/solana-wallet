import ModularArithmetic

/// SLIP-0010's NIST P-256 rules, which accept scalars from 1 to n - 1 as private keys.
struct P256Curve: DerivationCurve {
    /// A scalar modulo the order n of the curve's base point.
    private typealias Scalar = FieldElement<P256ScalarField>

    var label: String { "Nist256p1 seed" }

    func privateKey(candidate: [UInt8], parent: [UInt8]?) -> [UInt8]? {
        guard let tweak = Scalar(bigEndianBytes: candidate) else { return nil }
        guard let parent else { return tweak == .zero ? nil : candidate }
        let child = tweak + Scalar(reducing: parent)
        return child == .zero ? nil : child.bigEndianBytes
    }
}

extension DerivationCurve where Self == P256Curve {
    static var p256: Self { P256Curve() }
}
