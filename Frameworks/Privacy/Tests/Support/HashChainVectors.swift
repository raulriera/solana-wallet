import Testing

/// zolana's vectors of the chains that fold a transact proof's public inputs.
///
/// `HashChainVectors.json` copies, unchanged at tag v0.4.0-alpha (Apache-2.0), the vectors arrays
/// of `test-vectors/hash_chain_4.json` and `test-vectors/right_hash_chain_4.json`, and the
/// `tree_slots` section of `test-vectors/transact_derivation.json`.
/// `HashChainVectors-LICENSE.txt` records the sources and their digests. Elements and chains are
/// 32-byte big-endian hexadecimal field elements; small integers are JSON numbers.
struct HashChainVectors: Decodable, Sendable {
    /// Left chains of 0 to 54 elements, and one with a zero in the middle.
    let left4: [NonzeroHashChainVectors.Chain]

    /// Right chains of 0 to 54 elements, with zeros in the middle, trailing zeros, and only zeros.
    let right4: [NonzeroHashChainVectors.Chain]

    /// One tree slot, its hash, its chain, and the chains of unused slots.
    let treeSlots: TreeSlots

    /// The fixture's JSON keys.
    private enum CodingKeys: String, CodingKey {
        case left4 = "hash_chain_4"
        case right4 = "right_hash_chain_4"
        case treeSlots = "tree_slots"
    }

    /// A tree slot and the chains that fold it.
    struct TreeSlots: Decodable, Sendable {
        /// The slot's tree ID.
        let treeID: UInt16
        /// The slot's UTXO root, as an integer.
        let utxoRoot: UInt64
        /// The slot's nullifier root, as an integer.
        let nullifierRoot: UInt64
        /// The slot's hash.
        let slotHash: String
        /// The chain of the slot followed by 4 unused slots.
        let singleTreeChain: String
        /// The binary right chains of 1 to 4 unused slots.
        let zeroSuffixChains: [String]

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case treeID = "tree_id"
            case utxoRoot = "utxo_root"
            case nullifierRoot = "nullifier_root"
            case slotHash = "slot_hash"
            case singleTreeChain = "single_tree_chain"
            case zeroSuffixChains = "zero_suffix_chains"
        }
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The chain vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "HashChainVectors")
    }
}
