/// A request for the Groth16 proof of a default-ring confidential transfer on the prover's complete route.
///
/// The request carries the whole witness: each input's Merkle and non-inclusion proofs, which the caller reads
/// from an indexer, the declared trees' roots, and the full public input hash. Field elements are 32 big-endian
/// bytes. The witness holds secrets, such as the owner's nullifier secret, the blinding seed, amounts, and
/// blindings; the request's descriptions and reflection omit every value.
public struct TransferProofRequest: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
                                    CustomReflectable {
    /// A value that can't form a request.
    public enum ValidationError: Error, Sendable, Equatable {
        /// A field element or root isn't 32 bytes.
        case invalidLength
        /// A list doesn't have its count: one or two tree slots, three public slots, one published owner hash
        /// per output, or at least one input and output.
        case invalidCount
        /// An input names a tree slot that the request doesn't declare.
        case invalidTreeSlot
        /// An input's inclusion proof doesn't match it: only a real input that isn't cached has one.
        case invalidInclusionProof
        /// The read cache breaks zolana's rules: each list has no entry or one per input, each read index
        /// names an input, each cached input reads a nonzero hash, and the tree ID fits 16 bits and is zero
        /// without reads.
        case invalidCache
        /// The blinding seed is zero, which the prover rejects.
        case zeroBlindingSeed
    }

    /// A declared input tree and the roots that its inputs are proven against.
    public struct TreeSlot: Sendable, Equatable {
        /// The tree's ID.
        public let id: UInt16
        /// The 32-byte UTXO tree root.
        public let utxoRoot: [UInt8]
        /// The 32-byte nullifier tree root.
        public let nullifierRoot: [UInt8]

        /// Creates a tree slot.
        ///
        /// - Parameters:
        ///   - id: The tree's ID.
        ///   - utxoRoot: The 32-byte UTXO tree root.
        ///   - nullifierRoot: The 32-byte nullifier tree root.
        /// - Throws: ``ValidationError/invalidLength`` if a root isn't 32 bytes.
        public init(id: UInt16, utxoRoot: [UInt8], nullifierRoot: [UInt8]) throws {
            try TransferProofRequest.validateFields([utxoRoot, nullifierRoot])
            self.id = id
            self.utxoRoot = utxoRoot
            self.nullifierRoot = nullifierRoot
        }
    }

    /// The number of tree slots that every transfer proof publishes; unused slots are zero.
    static let treeSlotCount = 5

    /// The declared input trees' slots, one or two, in the order that real inputs first use them.
    public let treeSlots: [TreeSlot]
    /// The 32-byte public input hash of the transfer's statement with the tree slots.
    public let publicInputHash: [UInt8]
    /// The circuit's witness.
    public let witness: Witness

    /// Creates a request after checking that its parts agree.
    ///
    /// - Parameters:
    ///   - treeSlots: One or two declared trees in first-use order.
    ///   - publicInputHash: The 32-byte public input hash.
    ///   - witness: The circuit's witness.
    /// - Throws: A ``ValidationError`` if a count, length, tree slot, or inclusion proof is invalid.
    public init(treeSlots: [TreeSlot], publicInputHash: [UInt8], witness: Witness) throws {
        guard (1...2).contains(treeSlots.count) else { throw ValidationError.invalidCount }
        try Self.validateFields([publicInputHash])
        guard witness.inputs.allSatisfy({ Int($0.treeSlot) < treeSlots.count }) else { throw ValidationError.invalidTreeSlot }
        for (index, input) in witness.inputs.enumerated() {
            let isCached = witness.cacheIsCached.isEmpty ? false : witness.cacheIsCached[index]
            guard (input.inclusionProof == nil) == (input.isDummy || isCached) else {
                throw ValidationError.invalidInclusionProof
            }
        }
        self.treeSlots = treeSlots
        self.publicInputHash = publicInputHash
        self.witness = witness
    }

    /// A representation that omits the witness's secrets.
    public var description: String { "TransferProofRequest" }

    /// A debugging representation that omits the witness's secrets.
    public var debugDescription: String { description }

    /// A reflection without children, so dumps don't reveal the witness's secrets.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Checks that every value in each list is a 32-byte field element.
    ///
    /// - Parameter lists: The values to check.
    /// - Throws: ``ValidationError/invalidLength`` if a value has another length.
    static func validateFields(_ lists: [[UInt8]]...) throws {
        guard lists.allSatisfy({ $0.allSatisfy { $0.count == 32 } }) else { throw ValidationError.invalidLength }
    }
}
