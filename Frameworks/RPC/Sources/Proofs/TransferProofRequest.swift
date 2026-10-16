import Encoding

/// A request for the Groth16 proof of a default-ring confidential transfer on the prover's indexed route.
///
/// On this route the prover reads each real input's Merkle proof, each input's nullifier non-inclusion
/// proof, and the trees' roots itself, and reports them in the proof's ``TransferProof/Resolution``. Field
/// elements are 32 big-endian bytes. The witness holds secrets, such as the owner's nullifier secret, the
/// blinding seed, amounts, and blindings; the request's descriptions and reflection omit every value.
public struct TransferProofRequest: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
                                    CustomReflectable {
    /// A value that can't form a request.
    public enum ValidationError: Error, Sendable, Equatable {
        /// A field element, commitment, or nullifier isn't 32 bytes.
        case invalidLength
        /// A tree address isn't 32 bytes of base 58.
        case invalidAddress
        /// A list doesn't have its count: one or two trees, 17 public inputs, three public slots, one
        /// lookup per witness input, one published owner hash per output, or at least one input and output.
        case invalidCount
        /// An input names a tree that the request doesn't list, or its lookup and witness name different trees.
        case invalidTreeSlot
        /// A lookup disagrees with its witness input: only a real input that isn't cached has a commitment,
        /// and only compact padding, a padding input whose witness nullifier is zero, has a nullifier.
        case invalidLookup
        /// The read cache breaks zolana's rules: each list has no entry or one per input, each read index
        /// names an input, each cached input reads a nonzero hash, and the tree ID fits 16 bits and is zero
        /// without reads.
        case invalidCache
        /// The blinding seed is zero, which the prover rejects.
        case zeroBlindingSeed
    }

    /// A tree that the transfer's inputs come from, in the order that real inputs first use them.
    public struct Tree: Sendable, Equatable {
        /// The tree account's base-58 address.
        public let address: String
        /// The tree's ID.
        public let id: UInt16

        /// Creates a tree.
        ///
        /// - Parameters:
        ///   - address: The tree account's base-58 address.
        ///   - id: The tree's ID.
        /// - Throws: ``ValidationError/invalidAddress`` unless the address is 32 bytes of base 58.
        public init(address: String, id: UInt16) throws {
            guard Base58.decode(address, byteCount: 32) != nil else { throw ValidationError.invalidAddress }
            self.address = address
            self.id = id
        }
    }

    /// What the prover looks up for one input slot.
    public struct Input: Sendable, Equatable {
        /// The position of the input's tree in ``TransferProofRequest/trees``.
        public let treeSlot: UInt8
        /// The 32-byte UTXO hash of a real input, whose Merkle proof the prover reads, or `nil` for padding.
        public let commitment: [UInt8]?
        /// The 32-byte nullifier of compact padding, which the witness doesn't name, or `nil`.
        public let nullifier: [UInt8]?

        /// Creates an input lookup.
        ///
        /// - Parameters:
        ///   - treeSlot: The position of the input's tree.
        ///   - commitment: A real input's 32-byte UTXO hash, or `nil`.
        ///   - nullifier: Compact padding's 32-byte nullifier, or `nil`.
        /// - Throws: ``ValidationError/invalidLength`` if a value isn't 32 bytes.
        public init(treeSlot: UInt8, commitment: [UInt8]?, nullifier: [UInt8]?) throws {
            try TransferProofRequest.validateFields(commitment.map { [$0] } ?? [], nullifier.map { [$0] } ?? [])
            self.treeSlot = treeSlot
            self.commitment = commitment
            self.nullifier = nullifier
        }
    }

    /// The trees of the inputs, one or two.
    public let trees: [Tree]
    /// One lookup per input slot, in slot order.
    public let inputs: [Input]
    /// The 17 public inputs: the transfer's public statement without the tree-slot chain, which the prover inserts.
    public let publicInputs: [[UInt8]]
    /// The earliest slot of the prover's indexer reads, or `nil` for no minimum.
    public let minContextSlot: UInt64?
    /// The circuit's witness without Merkle paths and roots.
    public let witness: Witness

    /// The number of input slots, which selects the circuit with ``outputCount``.
    public var inputCount: Int { witness.inputs.count }

    /// The number of output slots.
    public var outputCount: Int { witness.outputs.count }

    /// Creates a request after checking that its parts agree.
    ///
    /// - Parameters:
    ///   - trees: One or two input trees in first-use order.
    ///   - inputs: One lookup per witness input.
    ///   - publicInputs: The 17 public inputs.
    ///   - minContextSlot: The earliest slot of the prover's reads, or `nil`.
    ///   - witness: The circuit's witness.
    /// - Throws: A ``ValidationError`` if a count, length, tree slot, or lookup is invalid.
    public init(trees: [Tree], inputs: [Input], publicInputs: [[UInt8]], minContextSlot: UInt64?, witness: Witness) throws {
        guard (1...2).contains(trees.count), inputs.count == witness.inputs.count, publicInputs.count == 17 else {
            throw ValidationError.invalidCount
        }
        try Self.validateFields(publicInputs)
        guard zip(inputs, witness.inputs).allSatisfy({ $0.treeSlot == $1.treeSlot && Int($0.treeSlot) < trees.count })
        else { throw ValidationError.invalidTreeSlot }
        for (index, (lookup, input)) in zip(inputs, witness.inputs).enumerated() {
            let isCached = witness.cacheIsCached.isEmpty ? false : witness.cacheIsCached[index]
            let isCompact = input.isDummy && input.nullifier.allSatisfy { $0 == 0 }
            guard (lookup.commitment == nil) == (input.isDummy || isCached), (lookup.nullifier != nil) == isCompact else {
                throw ValidationError.invalidLookup
            }
        }
        self.trees = trees
        self.inputs = inputs
        self.publicInputs = publicInputs
        self.minContextSlot = minContextSlot
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
