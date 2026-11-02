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

    static func utxo(isDummy: Bool = false) throws -> IndexedTransferProofRequest.UTXO {
        try IndexedTransferProofRequest.UTXO(domain: field(isDummy ? 1 : 3), owner: field(0x11), asset: field(0),
                                             amount: field(0xa1), blinding: field(0xb1), dataHash: field(0),
                                             ringDataHash: field(0), ringProgramID: field(0))
    }

    static func indexedTree(id: UInt16 = 0, address: [UInt8]? = nil) throws -> IndexedTransferProofRequest.Tree {
        try IndexedTransferProofRequest.Tree(id: id, address: address ?? Base58.decode(tree, byteCount: 32) ?? [])
    }

    static func indexedInput(isDummy: Bool = false, treeSlot: UInt8 = 0, nullifier: [UInt8] = field(0x21),
                             commitment: [UInt8]? = field(0xe1)) throws -> IndexedTransferProofRequest.Input {
        try IndexedTransferProofRequest.Input(
            utxo: utxo(isDummy: isDummy), isDummy: isDummy, treeSlot: treeSlot, nullifier: nullifier,
            ownerPublicKeyHash: field(0x31), nullifierSecret: field(0xc1), commitment: commitment
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
        try IndexedTransferProofRequest(
            trees: try trees ?? [indexedTree()],
            inputs: try inputs ?? [indexedInput()],
            outputs: [
                try .init(utxo: utxo(), isDummy: false, hash: field(0x41), ownerPublicKeyHash: field(0x31),
                          nullifierPublicKey: field(0x51)),
                try .init(utxo: utxo(isDummy: true), isDummy: true, hash: field(0x42), ownerPublicKeyHash: field(0x32),
                          nullifierPublicKey: field(0)),
            ],
            publicInputs: publicInputs,
            outputTreeID: 0x1a,
            blindingSeed: blindingSeed,
            publicAssets: [field(0), field(0), field(0)],
            publicAmounts: [field(0), field(0), field(0)],
            ringProgramID: field(0),
            signerPublicKeyHashes: [field(0x31), field(0)],
            inputFlags: field(1),
            publishedOutputOwnerPublicKeyHashes: [field(0x31), field(0x32)]
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
