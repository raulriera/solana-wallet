import ModularArithmetic
@testable import Privacy
import Testing

/// zolana's vectors of a transact proof's input flags and public input hash.
///
/// `PublicInputVectors.json` copies, unchanged at tag v0.4.0-alpha (Apache-2.0), the vectors array
/// of `test-vectors/input_flags.json`, the transfers array of `test-vectors/public_input_hash.json`,
/// and the whole of `sdk-libs/fixtures/indexed-proof.json`. `PublicInputVectors-LICENSE.txt`
/// records the sources and their digests. Field elements are 32-byte big-endian hexadecimal, and
/// the indexed proof's are `0x`-prefixed hexadecimal without padding.
struct PublicInputVectors: Decodable, Sendable {
    /// Input flags with and without padding inputs, from 1 to 49 inputs.
    let inputFlags: [Flags]

    /// Public input hashes of transfers.
    let transfers: [Transfer]

    /// The public inputs of a proof request and the hash after the prover inserts two trees' slots.
    let indexedProof: IndexedProof

    /// The fixture's JSON keys.
    private enum CodingKeys: String, CodingKey {
        case inputFlags = "input_flags"
        case transfers
        case indexedProof = "indexed_proof"
    }

    /// The input flags of a list of input trees.
    struct Flags: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name in the fixture.
        let name: String
        /// Whether padding inputs are allowed.
        let allowsDummyInputs: Bool
        /// Each input's tree position.
        let treeIndexes: [UInt8]
        /// The packed flags.
        let inputFlags: String

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case name
            case allowsDummyInputs = "allow_dummy_inputs"
            case treeIndexes = "tree_indexes"
            case inputFlags = "input_flags"
        }

        /// The vector's name, in test results.
        var testDescription: String { name }
    }

    /// A tree slot of a transfer.
    struct TreeSlot: Decodable, Sendable {
        /// The tree's ID.
        let id: UInt16
        /// The UTXO tree's root.
        let utxoRoot: String
        /// The nullifier tree's root.
        let nullifierRoot: String

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case id
            case utxoRoot = "utxo_root"
            case nullifierRoot = "nullifier_root"
        }

        /// Creates the slot.
        ///
        /// - Returns: The slot.
        /// - Throws: A test failure if a root is malformed or not canonical.
        func slot() throws -> PublicInputs.TreeSlot {
            PublicInputs.TreeSlot(treeID: id, utxoRoot: try Poseidon.Element(hex: utxoRoot), nullifierRoot: try Poseidon.Element(hex: nullifierRoot))
        }
    }

    /// A transfer's statement and its public input hash.
    struct Transfer: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name in the fixture.
        let name: String
        /// The input slots' nullifiers, zero for compact padding.
        let nullifiers: [String]
        /// The output slots' UTXO hashes.
        let outputHashes: [String]
        /// The output tree's ID.
        let outputTreeID: UInt16
        /// The private transaction hash.
        let privateTransactionHash: String
        /// The external data hash.
        let externalDataHash: String
        /// The public slots' assets.
        let publicAssets: [String]
        /// The public slots' amounts.
        let publicAmounts: [String]
        /// The ring program.
        let ringProgramID: String
        /// The packed input flags.
        let inputFlags: String
        /// The signer identities, at their full width.
        let signerIdentities: [String]
        /// The published output owner identities, which zeros complete to one per output; `nil` for
        /// a rail that publishes none.
        let outputOwnerIdentities: [String]?
        /// The cache's tree and read chain.
        let cachedInputs: [String]
        /// The 5 tree slots.
        let treeSlots: [TreeSlot]
        /// The public input hash.
        let publicInputHash: String

        /// The fixture's JSON keys.
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

        /// The vector's name, in test results.
        var testDescription: String { name }

        /// Creates the transfer's statement, completing its owner identities with zeros as the
        /// fixture describes.
        ///
        /// - Returns: The statement.
        /// - Throws: A test failure if a value is malformed or not canonical, or if the transfer
        ///   publishes no owner identities.
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

    /// A proof request's public inputs, its trees, and the prover's public input hash.
    struct IndexedProof: Decodable, Sendable {
        /// The 15 public inputs without the tree slots.
        let publicInputs: [String]
        /// The two trees.
        let trees: [Tree]
        /// The public input hash.
        let publicInputHash: String

        /// A tree that the prover resolved.
        struct Tree: Decodable, Sendable {
            /// The tree's ID.
            let id: UInt16
            /// The UTXO tree's root.
            let utxoRoot: String
            /// The nullifier tree's root.
            let nullifierRoot: String

            /// Creates the tree's slot.
            ///
            /// - Returns: The slot.
            /// - Throws: A test failure if a root is malformed or not canonical.
            func slot() throws -> PublicInputs.TreeSlot {
                PublicInputs.TreeSlot(
                    treeID: id, utxoRoot: try IndexedProof.element(utxoRoot), nullifierRoot: try IndexedProof.element(nullifierRoot)
                )
            }
        }

        /// Decodes a `0x`-prefixed hexadecimal field element, with or without zero padding.
        ///
        /// - Parameter text: The element.
        /// - Returns: The element.
        /// - Throws: A test failure if the element is malformed or not canonical.
        static func element(_ text: String) throws -> Poseidon.Element {
            let digits = try #require(text.hasPrefix("0x") ? text.dropFirst(2) : nil)
            return try Poseidon.Element(hex: String(repeating: "0", count: 64 - digits.count) + digits)
        }
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The public input vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "PublicInputVectors")
    }
}
