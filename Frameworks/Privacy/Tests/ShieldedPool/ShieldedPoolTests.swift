import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

struct ShieldedPoolTests {
    @Test(arguments: [
        (0, "33KVhbT4QtdQDrrrGwwThqD47Dh4Q6tA443t9jMNcWFN"),
        (1, "Cqu55AjGprSHJKs65Sw3P4zi1ZtJGy56jz91TyKmw3Cn"),
        (7, "4q8pT6x2J6b75gFFGjT3Fayh4jQMimTWpUVWQgVVmHiq"),
        (258, "2AE9CUkHJwarmurzwRjX82RimAuADmj5Au2fnsFRUadc"),
        (65_535, "BQbSMaPSP7xgx52QkPReMzhswayr2QZjwNxoCkzowuyT"),
    ] as [(UInt16, String)])
    func `Tree accounts match independently derived addresses`(id: UInt16, expected: String) throws {
        #expect(try ShieldedPool.tree(id: id).value == expected)
    }

    @Test
    func `Nullifier accounts match zolana's pinned vector`() throws {
        let tree = try Address("2RJD1KnDRGEkvuFfAGrJ7PD28LRE9LRDjZznDywagzmr")
        let nullifier = try Poseidon.Element(hex: String(repeating: "07", count: 32))

        #expect(try ShieldedPool.nullifierAccount(tree: tree, nullifier: nullifier).value == "HT4BbdfZvtEf5pDQHp5E3x4AV8qnTKFL4Bd13yhsK67w")
    }
}
