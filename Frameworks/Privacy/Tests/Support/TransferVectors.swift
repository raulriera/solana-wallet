import ModularArithmetic
@testable import Privacy
import Testing

/// zolana's byte-literal fixtures of two default-ring SOL transfers.
///
/// The values are the literals of `sdk-libs/transaction/tests/hash_vectors.rs` at tag
/// v0.4.0-alpha (Apache-2.0), copied unchanged as hexadecimal, with the amounts, blinding bytes,
/// and tree IDs that its fixtures pass. `CommitmentVectors-LICENSE.txt` records the source and its
/// digest. The sender is the Ed25519 rail of `key_derivation.json`, whose signing secret is 32
/// bytes of 7. Every UTXO holds SOL and carries no data. Case A spends one UTXO from tree 0 into
/// tree 0; case B spends UTXOs from trees 3 and 1 into tree 2. Output slot 0 belongs to a
/// recipient whose keys the fixtures don't publish, so its commitments are left out.
enum TransferVectors {
    /// An input slot: a UTXO that the sender spends, or an empty UTXO that pads the slot.
    struct Input: Sendable, CustomTestStringConvertible {
        /// The input's name in `hash_vectors.rs`.
        let name: String
        /// The amount in lamports, which is zero for padding.
        let amount: UInt64
        /// The byte that repeats after the blinding's leading zero.
        let blindingByte: UInt8
        /// The ID of the tree that holds the UTXO.
        let treeID: UInt16
        /// The UTXO's hash.
        let hash: String
        /// The nullifier: under the sender's nullifier secret for a spent UTXO, and under the zero
        /// secret for padding.
        let nullifier: String

        /// The input's name, in test results.
        var testDescription: String { name }
    }

    /// An output that the sender owns: the change in slot 1, or zero-amount padding in slots 2
    /// and 3.
    struct Output: Sendable, CustomTestStringConvertible {
        /// The output's name in `hash_vectors.rs`.
        let name: String
        /// The proof's first nullifier, which its output blindings derive from.
        let firstNullifier: String
        /// The ID of the output tree.
        let treeID: UInt16
        /// The output slot.
        let index: UInt32
        /// The amount in lamports.
        let amount: UInt64
        /// The output's UTXO hash.
        let commitment: String

        /// The output's name, in test results.
        var testDescription: String { name }
    }

    /// A proof's first nullifier and its private transaction blinding.
    struct Proof: Sendable, CustomTestStringConvertible {
        /// The proof's name in `hash_vectors.rs`.
        let name: String
        /// The nullifier of input slot 0.
        let firstNullifier: String
        /// The private transaction blinding.
        let privateTransactionBlinding: String

        /// The proof's name, in test results.
        var testDescription: String { name }
    }

    /// The first nullifier of case A, `CASE_A_FIRST_NULLIFIER`, which is also the nullifier of
    /// its input 0.
    private static let caseAFirstNullifier = "051737d4af5d70f1ccaeeefce207746efde8659fdaba87e213891592014fd988"

    /// The first nullifier of case B, `CASE_B_FIRST_NULLIFIER`, which is also the nullifier of
    /// its input 0.
    private static let caseBFirstNullifier = "2089309c50ba3a3d0061019331631a29efb6b1901eedfef33fe6b49a346c1538"

    /// The blinding seed of both proofs, `BLINDING_SEED`.
    static let blindingSeed = blinding(0x42)

    /// The UTXOs that the sender spends: case A's slot 0 and case B's slots 0 and 1.
    static let spentInputs = [
        Input(
            name: "CASE_A_INPUT_0", amount: 10, blindingByte: 0xa1, treeID: 0,
            hash: "11b80e57e9e87973648d049195cb4a95e75a9b69aac45abb9c4da81feec45f07",
            nullifier: caseAFirstNullifier
        ),
        Input(
            name: "CASE_B_INPUT_0", amount: 6, blindingByte: 0xb1, treeID: 3,
            hash: "0b62cde16bbd04c031a6f200771b3b701e4831ff340e70a4329f3d4c1ccab9ad",
            nullifier: caseBFirstNullifier
        ),
        Input(
            name: "CASE_B_INPUT_1", amount: 5, blindingByte: 0xb2, treeID: 1,
            hash: "00372d9f39c4ba7532053e22f8104c7b8106942ac79d3bee55f067a696cb8224",
            nullifier: "186418e504de218f2483df940e5b11a6773a566bf0ff1bff2ff8a262bd54c6d6"
        ),
    ]

    /// The empty UTXOs that pad input slots: case A's slot 1 and case B's slots 2 and 3.
    static let paddingInputs = [
        Input(
            name: "CASE_A_INPUT_1", amount: 0, blindingByte: 0xd1, treeID: 0,
            hash: "2a56f1f477bd23d3fdc52baadf6421f3f2bb6e8951d072b185f513d67f0f4b07",
            nullifier: "218402f389ccb54e99959e944e718ec4ffa2b870c17769f2b73e8ec963ba7163"
        ),
        Input(
            name: "CASE_B_INPUT_2", amount: 0, blindingByte: 0xd2, treeID: 3,
            hash: "131c29f83ada898de2ef9ef928d25b22e4fc99d929ef38c429aa9e6ae50c0e57",
            nullifier: "02b538b1f0e4621c7cc9601fab53c069c1ec2eadd5776b2a0704ce7b081d0911"
        ),
        Input(
            name: "CASE_B_INPUT_3", amount: 0, blindingByte: 0xd3, treeID: 3,
            hash: "04e69732b3a5669d68b72f7624551cd61a0d8df1ba93ace738d1400e363d23b5",
            nullifier: "0f457dac30259130c90597e178ffdbb25f2e7a6d2f479fed0b8c885898ae7b0e"
        ),
    ]

    /// The outputs that the sender owns, in slots 1 to 3 of both proofs.
    static let outputs = [
        Output(
            name: "CASE_A_OUTPUT_1", firstNullifier: caseAFirstNullifier, treeID: 0, index: 1, amount: 6,
            commitment: "10cd42ef147850211fffccf582240529c2ad01d3977d117b802bc287cac6cf96"
        ),
        Output(
            name: "CASE_A_OUTPUT_2", firstNullifier: caseAFirstNullifier, treeID: 0, index: 2, amount: 0,
            commitment: "01a9c2c6d77db3ac3d4b0af0711484ef83ee8a5df58879a8af76b8ad7f0700be"
        ),
        Output(
            name: "CASE_A_OUTPUT_3", firstNullifier: caseAFirstNullifier, treeID: 0, index: 3, amount: 0,
            commitment: "0a70347666902e32e1370240652b46c132cfb98df6ff041c804c0b221f2f2577"
        ),
        Output(
            name: "CASE_B_OUTPUT_1", firstNullifier: caseBFirstNullifier, treeID: 2, index: 1, amount: 7,
            commitment: "2ea8747e84688f914ec5300feab19b71ba46760bb5c1fb0976f50095f8ba7a7b"
        ),
        Output(
            name: "CASE_B_OUTPUT_2", firstNullifier: caseBFirstNullifier, treeID: 2, index: 2, amount: 0,
            commitment: "2e086bbb087b3ee4aa3366e289c23d5fbcefbbe95cbe9be6f41004ddb9ca33f5"
        ),
        Output(
            name: "CASE_B_OUTPUT_3", firstNullifier: caseBFirstNullifier, treeID: 2, index: 3, amount: 0,
            commitment: "2c4712b5aa34a1dbb65969c7190a2910a28c76fe9d3a4b224d4a9dd29c2712eb"
        ),
    ]

    /// Both proofs' private transaction blindings.
    static let proofs = [
        Proof(
            name: "CASE_A", firstNullifier: caseAFirstNullifier,
            privateTransactionBlinding: "277fcd432150317d6d856dfe4c1871dcacf7aa20cdde4e917efd830b6456e7fd"
        ),
        Proof(
            name: "CASE_B", firstNullifier: caseBFirstNullifier,
            privateTransactionBlinding: "08f38264c4c4f791b841d55fa6a48ce981609c141e223939e46d14e1774f0078"
        ),
    ]

    /// Returns a fixture blinding: a zero byte followed by 31 copies of one byte, as the
    /// `blinding` function of `hash_vectors.rs` builds it.
    ///
    /// - Parameter byte: The byte that repeats after the leading zero.
    /// - Returns: The blinding, which is below 2^248 and so below r.
    static func blinding(_ byte: UInt8) -> Poseidon.Element {
        Poseidon.Element(reducing: [0] + Array(repeating: byte, count: 31))
    }
}
