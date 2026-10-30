import ModularArithmetic
@testable import Privacy
import Testing

struct PublicInputVectors: Decodable, Sendable {
    let inputFlags: [Flags]

    let transfers: [Transfer]

    let indexedProof: IndexedProof

    private enum CodingKeys: String, CodingKey {
        case inputFlags = "input_flags"
        case transfers
        case indexedProof = "indexed_proof"
    }

    struct Flags: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let allowsDummyInputs: Bool
        let treeIndexes: [UInt8]
        let inputFlags: String

        private enum CodingKeys: String, CodingKey {
            case name
            case allowsDummyInputs = "allow_dummy_inputs"
            case treeIndexes = "tree_indexes"
            case inputFlags = "input_flags"
        }

        var testDescription: String { name }
    }

    struct TreeSlot: Decodable, Sendable {
        let id: UInt16
        let utxoRoot: String
        let nullifierRoot: String

        private enum CodingKeys: String, CodingKey {
            case id
            case utxoRoot = "utxo_root"
            case nullifierRoot = "nullifier_root"
        }

        func slot() throws -> PublicInputs.TreeSlot {
            PublicInputs.TreeSlot(treeID: id, utxoRoot: try Poseidon.Element(hex: utxoRoot), nullifierRoot: try Poseidon.Element(hex: nullifierRoot))
        }
    }

    struct Transfer: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let nullifiers: [String]
        let outputHashes: [String]
        let outputTreeID: UInt16
        let privateTransactionHash: String
        let externalDataHash: String
        let publicAssets: [String]
        let publicAmounts: [String]
        let ringProgramID: String
        let inputFlags: String
        let signerIdentities: [String]
        let outputOwnerIdentities: [String]?
        let cachedInputs: [String]
        let treeSlots: [TreeSlot]
        let publicInputHash: String

        private enum CodingKeys: String, CodingKey {
            case name
            case nullifiers
            case outputHashes = "output_hashes"
            case outputTreeID = "output_tree_id"
            case privateTransactionHash = "private_tx_hash"
            case externalDataHash = "external_data_hash"
            case publicAssets = "public_assets"
            case publicAmounts = "public_amounts"
            case ringProgramID = "ring_program_id"
            case inputFlags = "input_flags"
            case signerIdentities = "signer_pk_hashes"
            case outputOwnerIdentities = "output_owner_pk_hashes"
            case cachedInputs = "cached_inputs"
            case treeSlots = "tree_slots"
            case publicInputHash = "public_input_hash"
        }

        var testDescription: String { name }

        func publicInputs() throws -> PublicInputs {
            let elements = { (values: [String]) in try values.map { try Poseidon.Element(hex: $0) } }
            let owners = try elements(try #require(outputOwnerIdentities))
            let cache = try elements(cachedInputs)
            return PublicInputs(
                nullifiers: try elements(nullifiers), outputHashes: try elements(outputHashes), outputTreeID: outputTreeID,
                privateTransactionHash: try Poseidon.Element(hex: privateTransactionHash), externalDataHash: try Poseidon.Element(hex: externalDataHash),
                publicAssets: try elements(publicAssets), publicAmounts: try elements(publicAmounts), ringProgramID: try Poseidon.Element(hex: ringProgramID),
                signerIdentities: try elements(signerIdentities), inputFlags: try Poseidon.Element(hex: inputFlags),
                outputOwnerIdentities: owners + Array(repeating: .zero, count: outputHashes.count - owners.count),
                cacheTreeID: try #require(cache.first), cacheReadHashChain: try #require(cache.last)
            )
        }
    }

    struct IndexedProof: Decodable, Sendable {
        let publicInputs: [String]
        let trees: [Tree]
        let publicInputHash: String

        struct Tree: Decodable, Sendable {
            let id: UInt16
            let utxoRoot: String
            let nullifierRoot: String

            func slot() throws -> PublicInputs.TreeSlot {
                PublicInputs.TreeSlot(
                    treeID: id, utxoRoot: try IndexedProof.element(utxoRoot), nullifierRoot: try IndexedProof.element(nullifierRoot)
                )
            }
        }

        static func element(_ text: String) throws -> Poseidon.Element {
            let digits = try #require(text.hasPrefix("0x") ? text.dropFirst(2) : nil)
            return try Poseidon.Element(hex: String(repeating: "0", count: 64 - digits.count) + digits)
        }
    }

    static func load() throws -> Self {
        try fixture(named: "PublicInputVectors")
    }
}
