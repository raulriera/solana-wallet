@testable import Privacy
import Testing

/// Verifies proofs: their encoding and their part lengths.
struct TransactProofTests {
    /// Verifies that a proof writes `a`, `b`, and `c` in order as 192 bytes without lengths.
    @Test
    func `Proofs write their three points as 192 bytes`() throws {
        let proof = try TransactProof(a: Array(repeating: 1, count: 32), b: Array(repeating: 2, count: 128), c: Array(repeating: 3, count: 32))
        var writer = WincodeWriter()
        proof.write(to: &writer)

        #expect(writer.bytes == Array(repeating: 1, count: 32) + Array(repeating: 2, count: 128) + Array(repeating: 3, count: 32))
    }

    /// Verifies that a part of another length is rejected.
    ///
    /// - Parameter lengths: The lengths of `a`, `b`, and `c`, one of them wrong.
    @Test(arguments: [[31, 128, 32], [33, 128, 32], [32, 127, 32], [32, 129, 32], [32, 128, 0], [32, 128, 64]])
    func `Points of other lengths are rejected`(lengths: [Int]) {
        #expect(throws: TransactProof.ValidationError.invalidLength) {
            try TransactProof(
                a: Array(repeating: 1, count: lengths[0]), b: Array(repeating: 2, count: lengths[1]), c: Array(repeating: 3, count: lengths[2])
            )
        }
    }
}
