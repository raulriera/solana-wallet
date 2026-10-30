import Foundation
import RPC

enum ProofFixtures {
    static let tree = "33KVhbT4QtdQDrrrGwwThqD47Dh4Q6tA443t9jMNcWFN"

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
