@testable import ModularArithmetic

enum WideField: PrimeField {
    static let modulus = Modulus(0xf3b9_cac2_fc63_2551, 0xbce6_faad_a717_9e84, 0xffff_ffff_ffff_ffff, 0xffff_ffff_0000_0000)
}
