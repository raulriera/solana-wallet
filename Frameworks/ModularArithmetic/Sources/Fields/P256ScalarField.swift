/// The scalar field of the NIST P-256 (secp256r1) curve.
///
/// The modulus is the order of the curve's base point from [SEC 2](https://www.secg.org/sec2-v2.pdf),
/// section 2.4.2, and FIPS 186-5, whose curves NIST SP 800-186 specifies:
/// n = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551.
/// The modulus exceeds 2^255, so sums of two elements can carry above 256 bits.
public enum P256ScalarField: PrimeField {
    /// The modulus n.
    public static let modulus = Modulus(0xf3b9_cac2_fc63_2551, 0xbce6_faad_a717_9e84, 0xffff_ffff_ffff_ffff, 0xffff_ffff_0000_0000)
}
