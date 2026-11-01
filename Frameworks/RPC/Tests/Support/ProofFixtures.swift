import Encoding
import Foundation
import Testing
@testable import RPC

enum ProofFixtures {
    static let tree = "33KVhbT4QtdQDrrrGwwThqD47Dh4Q6tA443t9jMNcWFN"

    static let fieldOrder = "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"

    static let fieldOrderMinusOne = "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000"

    static let zeroAddress = String(repeating: "1", count: 32)

    static let zeroBytes = [UInt8](repeating: 0, count: 32)

    static func field(_ value: UInt8) -> [UInt8] { Array(repeating: 0, count: 31) + [value] }

    static func utxo(isDummy: Bool = false) throws -> TransferProofRequest.UTXO {
        try TransferProofRequest.UTXO(domain: field(isDummy ? 1 : 3), owner: field(0x11), asset: field(0),
                                      amount: field(0xa1), blinding: field(0xb1), dataHash: field(0),
                                      ringDataHash: field(0), ringProgramID: field(0))
    }

    static func inclusionProof() throws -> MerkleProof {
        try MerkleProof(leaf: Array(repeating: 0xff, count: 32), path: (1...32).map { field(UInt8($0)) }, leafIndex: 5,
                        root: field(0x71), rootIndex: 7)
    }

    static func nonInclusionProof() throws -> NonInclusionProof {
        try NonInclusionProof(nullifier: field(0x21), lowElement: field(0x20), lowElementIndex: 9, highElement: field(0x22),
                              path: (0x81...0xa8).map { field(UInt8($0)) }, root: field(0x72), rootIndex: 8)
    }

    static func witness(isDummy: Bool = false, hasInclusionProof: Bool = true, blindingSeed: [UInt8] = field(0xd1),
                        cacheTreeID: [UInt8] = field(0), cacheReadHashes: [[UInt8]] = [], cacheIsCached: [Bool] = [],
                        cacheReadIndexes: [UInt64] = []) throws -> TransferProofRequest.Witness {
        try TransferProofRequest.Witness(
            inputs: [try .init(utxo: utxo(isDummy: isDummy), isDummy: isDummy, treeSlot: 0, nullifier: field(0x21),
                               ownerPublicKeyHash: field(0x31), nullifierSecret: field(0xc1),
                               inclusionProof: hasInclusionProof ? try inclusionProof() : nil,
                               nonInclusionProof: try nonInclusionProof())],
            outputs: [
                try .init(utxo: utxo(), isDummy: false, hash: field(0x41), ownerPublicKeyHash: field(0x31),
                          nullifierPublicKey: field(0x51)),
                try .init(utxo: utxo(isDummy: true), isDummy: true, hash: field(0x42), ownerPublicKeyHash: field(0x32),
                          nullifierPublicKey: field(0)),
            ],
            outputTreeID: 0x1a,
            blindingSeed: blindingSeed,
            externalDataHash: field(0x61),
            privateTransactionHash: field(0x62),
            publicAssets: [field(0), field(0), field(0)],
            publicAmounts: [field(0), field(0), field(0)],
            ringProgramID: field(0),
            signerPublicKeyHashes: [field(0x31), field(0)],
            inputFlags: field(1),
            publishedOutputOwnerPublicKeyHashes: [field(0x31), field(0x32)],
            cacheTreeID: cacheTreeID,
            cacheReadHashChain: field(0),
            cacheReadHashes: cacheReadHashes,
            cacheIsCached: cacheIsCached,
            cacheReadIndexes: cacheReadIndexes
        )
    }

    static func treeSlot() throws -> TransferProofRequest.TreeSlot {
        try TransferProofRequest.TreeSlot(id: 0, utxoRoot: field(0x71), nullifierRoot: field(0x72))
    }

    static func request() throws -> TransferProofRequest {
        try TransferProofRequest(treeSlots: [treeSlot()], publicInputHash: field(0x99), witness: witness())
    }

    static func indexedTree(id: UInt16 = 0, address: [UInt8]? = nil) throws -> IndexedTransferProofRequest.Tree {
        try IndexedTransferProofRequest.Tree(id: id, address: address ?? Base58.decode(tree, byteCount: 32) ?? [])
    }

    static func indexedInput(isDummy: Bool = false, treeSlot: UInt8 = 0, nullifier: [UInt8]? = nil,
                             commitment: [UInt8]? = field(0xe1)) throws -> IndexedTransferProofRequest.Input {
        try indexedInput(from: witness(isDummy: isDummy).inputs[0], treeSlot: treeSlot, nullifier: nullifier,
                         commitment: commitment)
    }

    static func indexedInput(from input: TransferProofRequest.WitnessInput, treeSlot: UInt8? = nil,
                             nullifier: [UInt8]? = nil, commitment: [UInt8]? = field(0xe1)) throws
        -> IndexedTransferProofRequest.Input {
        try IndexedTransferProofRequest.Input(
            utxo: input.utxo, isDummy: input.isDummy, treeSlot: treeSlot ?? input.treeSlot,
            nullifier: nullifier ?? input.nullifier, ownerPublicKeyHash: input.ownerPublicKeyHash,
            nullifierSecret: input.nullifierSecret, commitment: commitment
        )
    }

    static func publicInputs(replacing index: Int? = nil, with value: [UInt8] = []) -> [[UInt8]] {
        let values: [UInt8] = [0x81, 0x82, 0x1a, 0x62, 0x61, 0, 0, 0, 0, 0, 0, 0, 0x83, 0x01, 0x84, 0, 0]
        var inputs = values.map(field)
        if let index { inputs[index] = value }
        return inputs
    }

    static func indexedRequest(trees: [IndexedTransferProofRequest.Tree]? = nil,
                               inputs: [IndexedTransferProofRequest.Input]? = nil,
                               publicInputs: [[UInt8]] = publicInputs(), blindingSeed: [UInt8] = field(0xd1)) throws
        -> IndexedTransferProofRequest {
        let witness = try witness()
        return try IndexedTransferProofRequest(
            trees: try trees ?? [indexedTree()],
            inputs: try inputs ?? witness.inputs.map { try indexedInput(from: $0) },
            outputs: witness.outputs,
            publicInputs: publicInputs,
            outputTreeID: witness.outputTreeID,
            blindingSeed: blindingSeed,
            publicAssets: witness.publicAssets,
            publicAmounts: witness.publicAmounts,
            ringProgramID: witness.ringProgramID,
            signerPublicKeyHashes: witness.signerPublicKeyHashes,
            inputFlags: witness.inputFlags,
            publishedOutputOwnerPublicKeyHashes: witness.publishedOutputOwnerPublicKeyHashes
        )
    }

    static func twoTreeRequest(publicInputs: [[UInt8]] = publicInputs()) throws -> IndexedTransferProofRequest {
        try indexedRequest(
            trees: [indexedTree(), indexedTree(id: 7, address: zeroBytes)],
            inputs: [indexedInput(), indexedInput(treeSlot: 1, commitment: field(0xe2)),
                     indexedInput(isDummy: true, commitment: nil)],
            publicInputs: publicInputs
        )
    }

    static let resolvedTrees = [
        resolvedTree(),
        resolvedTree(tree: #""\#(zeroAddress)""#, id: "7", utxoRoot: word(0x73), nullifierRoot: word(0x74),
                     utxoRootIndex: "9", nullifierRootIndex: "10"),
    ]

    static func resolvedTree(tree: String = #""\#(ProofFixtures.tree)""#, id: String = "0",
                             utxoRoot: String = word(0x71), nullifierRoot: String = word(0x72),
                             utxoRootIndex: String = "7", nullifierRootIndex: String = "8") -> String {
        #"{"tree":\#(tree),"id":\#(id),"utxoRoot":\#(utxoRoot),"nullifierRoot":\#(nullifierRoot),"#
            + #""utxoRootIndex":\#(utxoRootIndex),"nullifierRootIndex":\#(nullifierRootIndex)}"#
    }

    static func indexedResponse(trees: [String] = [resolvedTree()], publicInputHash: String = word(0x99)) -> String {
        String(response().dropLast())
            + #","resolution":{"trees":[\#(trees.joined(separator: ","))],"publicInputHash":\#(publicInputHash)}}"#
    }

    static func json(_ value: some Encodable) throws -> [String: AnyHashable] {
        try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: AnyHashable])
    }

    static func word(_ value: Int) -> String { #""0x\#(String(format: "%064x", value))""# }

    static func response(digest: String? = String(repeating: "7e", count: 32)) -> String {
        var fields = [
            #""ar":[\#(word(1)),\#(word(2))]"#,
            #""bs":[[\#(word(3)),\#(word(4))],[\#(word(5)),\#(word(6))]]"#,
            #""krs":[\#(word(7)),\#(word(8))]"#,
        ]
        if let digest { fields.append(#""provingKeySha256":"\#(digest)""#) }
        return "{" + fields.joined(separator: ",") + "}"
    }
}
