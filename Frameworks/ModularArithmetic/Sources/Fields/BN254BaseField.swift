/// The base field of the BN254 (alt_bn128) curve, which holds its points' coordinates.
///
/// The modulus is the field modulus from [EIP-196](https://eips.ethereum.org/EIPS/eip-196):
/// p = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47.
public enum BN254BaseField: PrimeField {
    /// The modulus p.
    public static let modulus = Modulus(0x3c20_8c16_d87c_fd47, 0x9781_6a91_6871_ca8d, 0xb850_45b6_8181_585d, 0x3064_4e72_e131_a029)
}
