/// A provider that reads private notes and proves private transfers with a Solana Rings client when it has the
/// ``Capabilities/privateBalances`` capability.
public protocol RingsProviding: RPC, PrivateNoteProviding, ProofProviding {
    /// The client for the provider's Solana Rings indexer and prover.
    var rings: Zolana { get }
}

extension RingsProviding {
    /// Reads one batch of the transactions with an output for any of the view tags, after a position, from the
    /// provider's Solana Rings indexer, or sends nothing when the provider lacks the
    /// ``Capabilities/privateBalances`` capability.
    ///
    /// - Parameters:
    ///   - tags: The 32-byte view tags.
    ///   - position: The position from an earlier read of the same tags, or `nil` to read from the start.
    /// - Returns: The transactions in slot and signature order, the tree for new outputs, the next read's position,
    ///   and whether more transactions come after it.
    /// - Throws: ``CapabilityError/missing(_:)`` without the capability, ``PrivateNoteError`` for an invalid tag or
    ///   position, or a request, transport, response, or cancellation error.
    public func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch {
        try await checkCapability(.privateBalances)
        return try await rings.shieldedTransactions(taggedWith: tags, after: position)
    }

    /// Reads the transactions that spent any of the nullifiers, up to the provider's limit for one read, from the
    /// provider's Solana Rings indexer, or sends nothing when the provider lacks the ``Capabilities/privateBalances``
    /// capability.
    ///
    /// - Parameter nullifiers: The 32-byte nullifiers.
    /// - Returns: Each spending transaction that the read reached once, in slot and signature order.
    /// - Throws: ``CapabilityError/missing(_:)`` without the capability, ``PrivateNoteError/invalidNullifier`` for a
    ///   nullifier that isn't 32 bytes, or a request, transport, response, or cancellation error.
    public func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction] {
        try await checkCapability(.privateBalances)
        return try await rings.shieldedTransactions(spending: nullifiers)
    }

    /// Reads the inclusion proofs of UTXO hashes in one tree from the provider's Solana Rings indexer, or sends
    /// nothing when the provider lacks the ``Capabilities/privateBalances`` capability.
    ///
    /// - Parameters:
    ///   - leaves: The 32-byte UTXO hashes.
    ///   - tree: The tree account's base-58 address.
    /// - Returns: The proofs that the provider returned for the leaves, in request order.
    /// - Throws: ``CapabilityError/missing(_:)`` without the capability, ``PrivateNoteError/invalidLeaf`` or
    ///   ``PrivateNoteError/invalidTree`` for an invalid leaf or tree, or a request, transport, response, or
    ///   cancellation error.
    public func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof] {
        try await checkCapability(.privateBalances)
        return try await rings.merkleProofs(for: leaves, inTree: tree)
    }

    /// Proves a confidential transfer with the provider's Solana Rings prover, or sends nothing when the provider
    /// lacks the ``Capabilities/privateBalances`` capability.
    ///
    /// - Parameter request: The transfer's trees, inputs with their commitments, witness, and public inputs.
    /// - Returns: The proof, the proving key's digest, and the roots that the prover proved the transfer against.
    /// - Throws: ``CapabilityError/missing(_:)`` without the capability, or a request, transport, response, or
    ///   cancellation error.
    public func proveTransfer(_ request: IndexedTransferProofRequest) async throws -> IndexedTransferProof {
        try await checkCapability(.privateBalances)
        return try await rings.proveTransfer(request)
    }

    /// Returns the ``Capabilities/privateBalances`` capability when the provider's server serves a Solana Rings indexer
    /// and a prover that the network's policy attests, whatever capabilities the client declares.
    ///
    /// - Returns: ``Capabilities/privateBalances`` when the indexer answers a read and the prover's attestation then
    ///   passes the network's policy, or no capabilities.
    /// - Throws: A rate-limit ``RPCError``, or `CancellationError`.
    public func privateBalancesCapability() async throws -> Capabilities {
        try await Capabilities(.privateBalances) {
            _ = try await rings.shieldedTransactions(spending: [[UInt8](repeating: 0, count: 32)])
            _ = try await rings.attestedKey.key()
            return true
        }
    }
}
