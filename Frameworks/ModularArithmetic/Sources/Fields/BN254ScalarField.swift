/// The scalar field of the BN254 (alt_bn128) curve.
///
/// The modulus is the curve's group order from [EIP-197](https://eips.ethereum.org/EIPS/eip-197):
/// r = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001.
public enum BN254ScalarField: PrimeField {
    /// The modulus r.
    public static let modulus = Modulus(0x43e1_f593_f000_0001, 0x2833_e848_79b9_7091, 0xb850_45b6_8181_585d, 0x3064_4e72_e131_a029)
}
