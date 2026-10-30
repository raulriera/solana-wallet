import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

struct ShieldedPoolTests {
    @Test(arguments: [
        (0, "777pvSGe5LaBd9nCczvE2FXEauiwtfGJ5XRpjKyniGor"),
        (1, "6kmoyYDZ7ECi8USmHVaePETKgyhLeiMEKMasGHSKqD13"),
        (7, "2jBVxLnY4tDYJqV34EptnNkXQJtB1yuDfW3mYiApaUa7"),
        (258, "CtMxz96yUoHQbTjcNxdtsA2Vw5rJa6ePYD6MLJVGf9jd"),
        (65_535, "3CWjvRtFw7ciFKXLKuenLzkyToYEM5pV9dmFWARHsuui"),
    ] as [(UInt16, String)])
    func `Tree accounts match independently derived addresses`(id: UInt16, expected: String) throws {
        #expect(try ShieldedPool.tree(id: id).value == expected)
    }

    @Test
    func `Nullifier accounts match zolana's pinned vector`() throws {
        let tree = try Address("2RJD1KnDRGEkvuFfAGrJ7PD28LRE9LRDjZznDywagzmr")
        let nullifier = try Poseidon.Element(hex: String(repeating: "07", count: 32))

        #expect(try ShieldedPool.nullifierAccount(tree: tree, nullifier: nullifier).value == "Ckb8uhoA4eDBNXphLtqkZvsHNmu2VXiMC8Uyxw9viGJR")
    }
}
