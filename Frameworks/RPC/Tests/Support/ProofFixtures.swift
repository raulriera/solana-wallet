import Foundation
import RPC

/// Fixture values for transfer proof requests and responses.
enum ProofFixtures {
    /// The devnet address of tree 0.
    static let tree = "33KVhbT4QtdQDrrrGwwThqD47Dh4Q6tA443t9jMNcWFN"

    /// A 32-byte big-endian field element of a small value.
    /// - Parameter value: The value's last byte.
    /// - Returns: Thirty-one zero bytes followed by `value`.
    static func field(_ value: UInt8) -> [UInt8] { Array(repeating: 0, count: 31) + [value] }

    /// A UTXO whose amount and blinding are recognizable secrets.
    /// - Parameter isDummy: Whether it pads a slot.
    /// - Returns: The UTXO.
    /// - Throws: A validation error, which these lengths don't produce.
    static func utxo(isDummy: Bool = false) throws -> TransferProofRequest.UTXO {
        try TransferProofRequest.UTXO(domain: field(isDummy ? 1 : 3), owner: field(0x11), asset: field(0),
                                      amount: field(0xa1), blinding: field(0xb1), dataHash: field(0),
                                      ringDataHash: field(0), ringProgramID: field(0))
    }

    /// A witness of one input and two outputs, one of them padding.
    /// - Parameters:
    ///   - isDummy: Whether the input pads its slot.
    ///   - nullifier: The input's published nullifier; zero marks compact padding.
    ///   - blindingSeed: The blinding seed.
    ///   - cacheTreeID: The read cache's tree ID.
    ///   - cacheReadHashes: The cached hashes.
    ///   - cacheIsCached: Whether the input is cached.
    ///   - cacheReadIndexes: The input's read position.
    /// - Returns: The witness.
    /// - Throws: A validation error for invalid values.
    static func witness(isDummy: Bool = false, nullifier: [UInt8] = field(0x21), blindingSeed: [UInt8] = field(0xd1),
                        cacheTreeID: [UInt8] = field(0), cacheReadHashes: [[UInt8]] = [], cacheIsCached: [Bool] = [],
                        cacheReadIndexes: [UInt64] = []) throws -> TransferProofRequest.Witness {
        try TransferProofRequest.Witness(
            inputs: [try .init(utxo: utxo(isDummy: isDummy), isDummy: isDummy, treeSlot: 0, nullifier: nullifier,
                               ownerPublicKeyHash: field(0x31), nullifierSecret: field(0xc1))],
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

    /// A request for the fixture witness from tree 0.
    /// - Returns: The request.
    /// - Throws: A validation error, which these values don't produce.
    static func request() throws -> TransferProofRequest {
        try TransferProofRequest(
            trees: [try .init(address: tree, id: 0)],
            inputs: [try .init(treeSlot: 0, commitment: Array(repeating: 0xff, count: 32), nullifier: nil)],
            publicInputs: (1...17).map { field(UInt8($0)) },
            minContextSlot: 99,
            witness: witness()
        )
    }

    /// A quoted 64-digit hexadecimal word, as the prover pads coordinates.
    /// - Parameter value: The word's value.
    /// - Returns: The JSON string.
    static func word(_ value: Int) -> String { #""0x\#(String(format: "%064x", value))""# }

    /// A prover response with zero-padded coordinates.
    /// - Parameters:
    ///   - digest: The `provingKeySha256` member, or `nil` to omit it.
    ///   - resolution: Whether to include the resolution.
    /// - Returns: The response body's JSON text.
    static func response(digest: String? = String(repeating: "7e", count: 32), resolution: Bool = true) -> String {
        var fields = [
            #""ar":[\#(word(1)),\#(word(2))]"#,
            #""bs":[[\#(word(3)),\#(word(4))],[\#(word(5)),\#(word(6))]]"#,
            #""krs":[\#(word(7)),\#(word(8))]"#,
        ]
        if let digest { fields.append(#""provingKeySha256":"\#(digest)""#) }
        if resolution {
            fields.append("""
                "resolution":{"trees":[{"tree":"\(tree)","id":0,"utxoRoot":"0xa","nullifierRoot":\(word(11)),\
                "utxoRootIndex":499,"nullifierRootIndex":7}],"publicInputHash":"0x123"}
                """)
        }
        return "{" + fields.joined(separator: ",") + "}"
    }
}
