import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

/// zolana's byte-literal fixtures of two default-ring SOL transfers.
///
/// The values are the literals of `sdk-libs/transaction/tests/hash_vectors.rs` at tag
/// v0.4.0-alpha (Apache-2.0), copied unchanged as hexadecimal, with the amounts, blinding bytes,
/// and tree IDs that its fixtures pass. `CommitmentVectors-LICENSE.txt` records the source and its
/// digest. The sender is the Ed25519 rail of `key_derivation.json`, whose signing secret is 32
/// bytes of 7. Every UTXO holds SOL and carries no data. Case A spends one UTXO from tree 0 into
/// tree 0; case B spends UTXOs from trees 3 and 1 into tree 2. Output slot 0 belongs to the
/// recipient, the Ed25519 rail of signing secret 32 bytes of 9, whose keys zolana doesn't publish;
/// a separate Python implementation of RFC 8032 signing and zolana's rail derivation supplies them,
/// and they reproduce both published slot-0 commitments. Both cases seal every output's note with
/// the salt of 16 bytes of 0x5a; case A's fee payer is the sender and case B's is the relayed payer
/// of 32 bytes of 3.
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

        /// Derives the output's blinding from its proof's first nullifier and the published
        /// blinding seed, through the output blinding seed.
        ///
        /// - Returns: The output's blinding.
        /// - Throws: A test failure if the first nullifier is malformed or not canonical.
        func blinding() throws -> Poseidon.Element {
            let nullifier = try Poseidon.Element(hex: firstNullifier)
            let outputBlindingSeed = TransactBlinding.outputBlindingSeed(firstNullifier: nullifier, blindingSeed: TransferVectors.blindingSeed)
            return TransactBlinding.outputBlinding(firstNullifier: nullifier, outputBlindingSeed: outputBlindingSeed, index: index)
        }
    }

    /// One whole transfer: its slots and the hashes that `hash_vectors.rs` publishes for it.
    struct Transfer: Sendable, CustomTestStringConvertible {
        /// The transfer's name in `hash_vectors.rs`.
        let name: String
        /// The nullifier of input slot 0.
        let firstNullifier: String
        /// The ID of the output tree.
        let outputTreeID: UInt16
        /// The spent inputs, in slot order before the padding.
        let spentInputs: [Input]
        /// The padding inputs, which hash as zero.
        let paddingInputs: [Input]
        /// The recipient's amount in output slot 0.
        let recipientAmount: UInt64
        /// The recipient's UTXO hash in output slot 0.
        let recipientCommitment: String
        /// The sender's outputs in slots 1 to 3.
        let senderOutputs: [Output]
        /// The fee payer's address.
        let payer: String
        /// The external data hash.
        let externalDataHash: String
        /// The private transaction hash.
        let privateTransactionHash: String

        /// The transfer's name, in test results.
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

    /// The salt of both transfers' notes, `SALT`.
    static let salt = [UInt8](repeating: 0x5a, count: 16)

    /// The recipient's Ed25519 signing address, the public key of signing secret 32 bytes of 9.
    static let recipientSigningAddress = "J2xccRtuG43drESLYznHhLhQkLTdfepcKYbiQ9BsJVaf"

    /// The recipient's nullifier public key, independently derived.
    static let recipientNullifierPublicKey = "07f313f2ef546c5ac079f4591e978eaaa944e2ffee4dd5c5fa2156ff39e84856"

    /// The recipient's 32-byte P-256 viewing secret, independently derived.
    static let recipientViewingSecret = "e1eba2fc69ef567562725af78342749ef7af2a63251ae2343c7e789522dccfa2"

    /// The sender's Ed25519 signing address, the Ed25519 rail's `signer_pubkey`.
    static let senderSigningAddress = "GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB"

    /// Both transfers, with the values that `hash_vectors.rs` publishes for them.
    static let transfers = [
        Transfer(
            name: "CASE_A", firstNullifier: caseAFirstNullifier, outputTreeID: 0,
            spentInputs: [spentInputs[0]], paddingInputs: [paddingInputs[0]], recipientAmount: 4,
            recipientCommitment: "2e594a80158648b6dab780fd6e3cb9562df793ba52fcae62da52bcfd71db4360",
            senderOutputs: Array(outputs[0..<3]), payer: senderSigningAddress,
            externalDataHash: "00dbaa00ad37765ac297258d4c5ee6ed81efea1beea765f593835efb20755e1f",
            privateTransactionHash: "2fc2151ff99263248e517ea9b1c64907b45cae11ceea497833051a7ab6582174"
        ),
        Transfer(
            name: "CASE_B", firstNullifier: caseBFirstNullifier, outputTreeID: 2,
            spentInputs: Array(spentInputs[1...2]), paddingInputs: Array(paddingInputs[1...2]), recipientAmount: 4,
            recipientCommitment: "1923c73dd6386bc75c4a72a75ca31185928a174f0206d9fc71b0af597b8f7219",
            senderOutputs: Array(outputs[3..<6]), payer: "CktRuQ2mttgRGkXJtyksdKHjUdc2C4TgDzyB98oEzy8",
            externalDataHash: "00eaf658e5b067715f37535419f0de68b3438045ee9943c6fcff06437b2404d2",
            privateTransactionHash: "09237d093e2622323e34fb3cd86e1ae0f26e20078c0d82a82be86b6c607c854a"
        ),
    ]

    /// Creates the recipient's viewing key from its independently derived secret.
    ///
    /// - Returns: The viewing key.
    /// - Throws: A test failure if the secret is malformed, or a CryptoKit error if it isn't a
    ///   P-256 private key.
    static func recipientViewingKey() throws -> P256.KeyAgreement.PrivateKey {
        try P256.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(recipientViewingSecret))
    }

    /// Creates the recipient of output slot 0 from its independently derived keys.
    ///
    /// - Returns: The recipient.
    /// - Throws: A test failure if a key is malformed, or an error if a key isn't valid.
    static func recipient() throws -> Recipient {
        try Recipient(
            signingAddress: Address(recipientSigningAddress), nullifierPublicKey: Poseidon.Element(hex: recipientNullifierPublicKey),
            viewingPublicKey: recipientViewingKey().publicKey
        )
    }

    /// Creates the sender, zolana's Ed25519 rail, from its published keys.
    ///
    /// - Returns: The sender.
    /// - Throws: A test failure if the fixture is missing or malformed, or an error if a key isn't
    ///   valid.
    static func sender() throws -> ShieldedAccount {
        let rail = try CommitmentVectors.load().ed25519Rail
        return try ShieldedAccount(
            signingAddress: Address(senderSigningAddress), nullifierSecret: rail.nullifierSecretKey(),
            viewingKey: rail.viewingKey()
        )
    }

    /// Returns a fixture blinding: a zero byte followed by 31 copies of one byte, as the
    /// `blinding` function of `hash_vectors.rs` builds it.
    ///
    /// - Parameter byte: The byte that repeats after the leading zero.
    /// - Returns: The blinding, which is below 2^248 and so below r.
    static func blinding(_ byte: UInt8) -> Poseidon.Element {
        Poseidon.Element(reducing: [0] + Array(repeating: byte, count: 31))
    }
}
