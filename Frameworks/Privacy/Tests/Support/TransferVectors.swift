import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

enum TransferVectors {
    struct Input: Sendable, CustomTestStringConvertible {
        let name: String
        let amount: UInt64
        let blindingByte: UInt8
        let treeID: UInt16
        let hash: String
        let nullifier: String

        var testDescription: String { name }
    }

    struct Output: Sendable, CustomTestStringConvertible {
        let name: String
        let firstNullifier: String
        let treeID: UInt16
        let index: UInt32
        let amount: UInt64
        let commitment: String

        var testDescription: String { name }

        func blinding() throws -> Poseidon.Element {
            let nullifier = try Poseidon.Element(hex: firstNullifier)
            let outputBlindingSeed = TransactBlinding.outputBlindingSeed(firstNullifier: nullifier, blindingSeed: TransferVectors.blindingSeed)
            return TransactBlinding.outputBlinding(firstNullifier: nullifier, outputBlindingSeed: outputBlindingSeed, index: index)
        }
    }

    struct Transfer: Sendable, CustomTestStringConvertible {
        let name: String
        let firstNullifier: String
        let outputTreeID: UInt16
        let spentInputs: [Input]
        let paddingInputs: [Input]
        let recipientAmount: UInt64
        let recipientCommitment: String
        let senderOutputs: [Output]
        let payer: String
        let externalDataHash: String
        let privateTransactionHash: String

        var testDescription: String { name }
    }

    struct Proof: Sendable, CustomTestStringConvertible {
        let name: String
        let firstNullifier: String
        let privateTransactionBlinding: String

        var testDescription: String { name }
    }

    private static let caseAFirstNullifier = "051737d4af5d70f1ccaeeefce207746efde8659fdaba87e213891592014fd988"

    private static let caseBFirstNullifier = "2089309c50ba3a3d0061019331631a29efb6b1901eedfef33fe6b49a346c1538"

    static let blindingSeed = blinding(0x42)

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

    static let salt = [UInt8](repeating: 0x5a, count: 16)

    static let recipientSigningAddress = "J2xccRtuG43drESLYznHhLhQkLTdfepcKYbiQ9BsJVaf"

    static let recipientNullifierPublicKey = "07f313f2ef546c5ac079f4591e978eaaa944e2ffee4dd5c5fa2156ff39e84856"

    static let recipientViewingSecret = "a8369644de220446321de5410792cfb005042b47f9a76465491fc989b93e7559"

    static let senderSigningAddress = "GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB"

    static let transfers = [
        Transfer(
            name: "CASE_A", firstNullifier: caseAFirstNullifier, outputTreeID: 0,
            spentInputs: [spentInputs[0]], paddingInputs: [paddingInputs[0]], recipientAmount: 4,
            recipientCommitment: "2e594a80158648b6dab780fd6e3cb9562df793ba52fcae62da52bcfd71db4360",
            senderOutputs: Array(outputs[0..<3]), payer: senderSigningAddress,
            externalDataHash: "002a88dc591199db4a5fbff4d3ca4b5a91a03e3e7725b7941493266f6d4baec0",
            privateTransactionHash: "2fc2151ff99263248e517ea9b1c64907b45cae11ceea497833051a7ab6582174"
        ),
        Transfer(
            name: "CASE_B", firstNullifier: caseBFirstNullifier, outputTreeID: 2,
            spentInputs: Array(spentInputs[1...2]), paddingInputs: Array(paddingInputs[1...2]), recipientAmount: 4,
            recipientCommitment: "1923c73dd6386bc75c4a72a75ca31185928a174f0206d9fc71b0af597b8f7219",
            senderOutputs: Array(outputs[3..<6]), payer: "CktRuQ2mttgRGkXJtyksdKHjUdc2C4TgDzyB98oEzy8",
            externalDataHash: "008b0b53cde788829f896d8d4d45fbca6f5f9228e2079e9b7806c92f0f36a519",
            privateTransactionHash: "09237d093e2622323e34fb3cd86e1ae0f26e20078c0d82a82be86b6c607c854a"
        ),
    ]

    static func recipientViewingKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(recipientViewingSecret))
    }

    static func recipient() throws -> Recipient {
        try Recipient(
            signingAddress: Address(recipientSigningAddress), nullifierPublicKey: Poseidon.Element(hex: recipientNullifierPublicKey),
            viewingPublicKey: recipientViewingKey().publicKey
        )
    }

    static func sender() throws -> ShieldedAccount {
        let rail = try CommitmentVectors.load().ed25519Rail
        return try ShieldedAccount(
            signingAddress: Address(senderSigningAddress), nullifierSecret: rail.nullifierSecretKey(),
            viewingKey: rail.viewingKey()
        )
    }

    static func blinding(_ byte: UInt8) -> Poseidon.Element {
        Poseidon.Element(reducing: [0] + Array(repeating: byte, count: 31))
    }
}
