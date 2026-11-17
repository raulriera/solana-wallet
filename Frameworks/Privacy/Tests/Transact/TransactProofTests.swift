import Testing
@testable import Privacy

struct TransactProofTests {
    @Test(arguments: [[31, 128, 32], [33, 128, 32], [32, 127, 32], [32, 129, 32], [32, 128, 0], [32, 128, 64]])
    func `Points of other lengths are rejected`(lengths: [Int]) {
        #expect(throws: TransactProof.ValidationError.invalidLength) {
            try TransactProof(
                a: Array(repeating: 1, count: lengths[0]), b: Array(repeating: 2, count: lengths[1]), c: Array(repeating: 3, count: lengths[2])
            )
        }
    }
}
