import RPC
import Testing

struct TransferProofTests {
    private static func proof(a: [UInt8] = [1], b: [UInt8] = [2], c: [UInt8] = [5], digest: [UInt8] = [3]) -> TransferProof {
        TransferProof(a: .init(x: a, y: [0]), b: b, c: .init(x: c, y: [6]), provingKeyDigest: digest)
    }

    @Test(arguments: [proof(a: [9]), proof(b: [9]), proof(c: [9]), proof(digest: [9])])
    func `Proofs differ when any part differs`(other: TransferProof) {
        #expect(other != Self.proof())
        #expect(Self.proof() == Self.proof())
    }

    @Test(arguments: [TransferProof.G1Point(x: [9], y: [2]), .init(x: [1], y: [9])])
    func `Points differ when a coordinate differs`(other: TransferProof.G1Point) {
        #expect(other != TransferProof.G1Point(x: [1], y: [2]))
    }
}
