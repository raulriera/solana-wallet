import Testing

struct HashChainVectors: Decodable, Sendable {
    let left4: [NonzeroHashChainVectors.Chain]

    let right4: [NonzeroHashChainVectors.Chain]

    let treeSlots: TreeSlots

    private enum CodingKeys: String, CodingKey {
        case left4 = "hash_chain_4"
        case right4 = "right_hash_chain_4"
        case treeSlots = "tree_slots"
    }

    struct TreeSlots: Decodable, Sendable {
        let treeID: UInt16
        let utxoRoot: UInt64
        let nullifierRoot: UInt64
        let slotHash: String
        let singleTreeChain: String
        let zeroSuffixChains: [String]

        private enum CodingKeys: String, CodingKey {
            case treeID = "tree_id"
            case utxoRoot = "utxo_root"
            case nullifierRoot = "nullifier_root"
            case slotHash = "slot_hash"
            case singleTreeChain = "single_tree_chain"
            case zeroSuffixChains = "zero_suffix_chains"
        }
    }

    static func load() throws -> Self {
        try fixture(named: "HashChainVectors")
    }
}
