/// A provider that reads private notes and proves private transfers with a Solana Rings client.
///
/// Without the ``Capabilities/privateBalances`` capability, its private-note reads and proofs throw
/// ``CapabilityError/missing(_:)``.
public protocol RingsProviding: RPC, PrivateNoteProviding, ProofProviding {
    /// The client for the provider's Solana Rings indexer and prover.
    var rings: Zolana { get }
}

extension RingsProviding {
    public func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch {
        try await checkCapability(.privateBalances)
        return try await rings.shieldedTransactions(taggedWith: tags, after: position)
    }

    public func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction] {
        try await checkCapability(.privateBalances)
        return try await rings.shieldedTransactions(spending: nullifiers)
    }

    public func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof] {
        try await checkCapability(.privateBalances)
        return try await rings.merkleProofs(for: leaves, inTree: tree)
    }

    public func proveTransfer(_ request: IndexedTransferProofRequest) async throws -> IndexedTransferProof {
        try await checkCapability(.privateBalances)
        return try await rings.proveTransfer(request)
    }

    /// Checks whether the provider's server serves private balances, whatever the client declares.
    ///
    /// - Returns: ``Capabilities/privateBalances`` when the indexer answers and the prover's attestation passes the
    ///   network's policy, or no capabilities.
    /// - Throws: A rate-limit ``RPCError``, or `CancellationError`.
    public func privateBalancesCapability() async throws -> Capabilities {
        try await Capabilities(.privateBalances) {
            _ = try await rings.shieldedTransactions(spending: [[UInt8](repeating: 0, count: 32)])
            _ = try await rings.attestedKey.key()
            return true
        }
    }
}
