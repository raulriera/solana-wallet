import Encoding
import Foundation
import Testing
@testable import RPC

enum ProofFixtures {
    static let fieldOrder = "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"

    static let fieldOrderMinusOne = "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000"

    static func utxo(isDummy: Bool = false) throws -> IndexedTransferProofRequest.UTXO {
        try IndexedTransferProofRequest.UTXO(domain: fieldElement(isDummy ? 1 : 3), owner: fieldElement(0x11),
                                             asset: fieldElement(0), amount: fieldElement(0xa1),
                                             blinding: fieldElement(0xb1), dataHash: fieldElement(0),
                                             ringDataHash: fieldElement(0), ringProgramID: fieldElement(0))
    }

    static func indexedTree(id: UInt16 = 0, address: [UInt8]? = nil) throws -> IndexedTransferProofRequest.Tree {
        try IndexedTransferProofRequest.Tree(
            id: id, address: address ?? Base58.decode(ProverAnswer.treeAddress, byteCount: 32) ?? []
        )
    }

    static func indexedInput(isDummy: Bool = false, treeSlot: UInt8 = 0, nullifier: [UInt8] = fieldElement(0x21),
                             commitment: [UInt8]? = fieldElement(0xe1)) throws -> IndexedTransferProofRequest.Input {
        try IndexedTransferProofRequest.Input(
            utxo: utxo(isDummy: isDummy), isDummy: isDummy, treeSlot: treeSlot, nullifier: nullifier,
            ownerPublicKeyHash: fieldElement(0x31), nullifierSecret: fieldElement(0xc1), commitment: commitment
        )
    }

    static func publicInputs(replacing index: Int? = nil, with value: [UInt8] = []) -> [[UInt8]] {
        let values: [UInt8] = [0x81, 0x82, 0x1a, 0x62, 0x61, 0, 0, 0, 0, 0, 0, 0, 0x83, 0x01, 0x84, 0, 0]
        var inputs = values.map(fieldElement)
        if let index { inputs[index] = value }
        return inputs
    }

    static func indexedRequest(trees: [IndexedTransferProofRequest.Tree]? = nil,
                               inputs: [IndexedTransferProofRequest.Input]? = nil,
                               publicInputs: [[UInt8]] = publicInputs(), blindingSeed: [UInt8] = fieldElement(0xd1))
        throws -> IndexedTransferProofRequest {
        try IndexedTransferProofRequest(
            trees: try trees ?? [indexedTree()],
            inputs: try inputs ?? [indexedInput()],
            outputs: [
                try .init(utxo: utxo(), isDummy: false, hash: fieldElement(0x41),
                          ownerPublicKeyHash: fieldElement(0x31), nullifierPublicKey: fieldElement(0x51)),
                try .init(utxo: utxo(isDummy: true), isDummy: true, hash: fieldElement(0x42),
                          ownerPublicKeyHash: fieldElement(0x32), nullifierPublicKey: fieldElement(0)),
            ],
            publicInputs: publicInputs,
            outputTreeID: 0x1a,
            blindingSeed: blindingSeed,
            publicAssets: [fieldElement(0), fieldElement(0), fieldElement(0)],
            publicAmounts: [fieldElement(0), fieldElement(0), fieldElement(0)],
            ringProgramID: fieldElement(0),
            signerPublicKeyHashes: [fieldElement(0x31), fieldElement(0)],
            inputFlags: fieldElement(1),
            publishedOutputOwnerPublicKeyHashes: [fieldElement(0x31), fieldElement(0x32)]
        )
    }

    static func twoTreeRequest(publicInputs: [[UInt8]] = publicInputs()) throws -> IndexedTransferProofRequest {
        try indexedRequest(
            trees: [indexedTree(), indexedTree(id: 7, address: fieldElement(0))],
            inputs: [indexedInput(), indexedInput(treeSlot: 1, commitment: fieldElement(0xe2)),
                     indexedInput(isDummy: true, commitment: nil)],
            publicInputs: publicInputs
        )
    }

    static func json(_ value: some Encodable) throws -> [String: AnyHashable] {
        try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: AnyHashable])
    }
}
