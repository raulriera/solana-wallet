/// A request for the Groth16 proof of a default-ring confidential transfer.
public struct TransferProofRequest: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
                                    CustomReflectable {
    /// An error for a value that can't form a request.
    public enum ValidationError: Error, Sendable, Equatable {
        /// A field element or root isn't 32 bytes.
        case invalidLength
        /// A list doesn't have its required number of entries.
        case invalidCount
        /// An input names a tree slot that the request doesn't declare.
        case invalidTreeSlot
        /// An input's inclusion proof is missing or unexpected.
        case invalidInclusionProof
        /// The read cache's lists, read indexes, or tree ID don't match the inputs.
        case invalidCache
        case zeroBlindingSeed
    }

    /// A declared input tree and the roots that its inputs are proven against.
    public struct TreeSlot: Sendable, Equatable {
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

    /// The number of tree slots that every transfer proof publishes.
    static let treeSlotCount = 5

    /// The one or two declared input trees, in the order that real inputs first use them.
    public let treeSlots: [TreeSlot]
    /// The 32-byte public input hash of the transfer's statement with the tree slots.
    public let publicInputHash: [UInt8]
    public let witness: Witness

    /// Creates a request.
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

    public var description: String { "TransferProofRequest" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Checks that every value in each list is a 32-byte field element.
    ///
    /// - Parameter lists: The values to check.
    /// - Throws: ``ValidationError/invalidLength`` if a value has another length.
    static func validateFields(_ lists: [[UInt8]]...) throws {
        guard lists.allSatisfy({ $0.allSatisfy { $0.count == 32 } }) else { throw ValidationError.invalidLength }
    }
}
