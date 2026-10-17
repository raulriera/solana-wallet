import Testing
import RPC

/// Verifies the identity of transfer proofs and their parts.
struct TransferProofTests {
    /// Creates a proof with optional changes.
    /// - Parameters:
    ///   - a: The point `a`.
    ///   - b: The point `b`.
    ///   - c: The point `c`.
    ///   - digest: The proving key digest.
    /// - Returns: The proof.
    private static func proof(a: [UInt8] = [1], b: [UInt8] = [2], c: [UInt8] = [5], digest: [UInt8] = [3]) -> TransferProof {
        TransferProof(a: .init(x: a, y: [0]), b: b, c: .init(x: c, y: [6]), provingKeyDigest: digest)
    }

    /// Verifies proofs are equal only when their points and digest are.
    ///
    /// - Parameter other: The proof with one part changed.
    @Test(arguments: [proof(a: [9]), proof(b: [9]), proof(c: [9]), proof(digest: [9])])
    func `Proofs differ when any part differs`(other: TransferProof) {
        #expect(other != Self.proof())
        #expect(Self.proof() == Self.proof())
    }

    /// Verifies points are equal only when both coordinates are.
    ///
    /// - Parameter other: The point with one coordinate changed.
    @Test(arguments: [TransferProof.G1Point(x: [9], y: [2]), .init(x: [1], y: [9])])
    func `Points differ when a coordinate differs`(other: TransferProof.G1Point) {
        #expect(other != TransferProof.G1Point(x: [1], y: [2]))
    }
}
