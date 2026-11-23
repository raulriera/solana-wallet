/// A provider that reads private notes and proves private transfers with a Solana Rings client.
public protocol RingsProviding: PrivateNoteProviding, ProofProviding {
    /// The client for the provider's Solana Rings indexer and prover.
    var rings: Zolana { get }
}

extension RingsProviding {
    public func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch {
        try await rings.shieldedTransactions(taggedWith: tags, after: position)
    }

    public func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction] {
        try await rings.shieldedTransactions(spending: nullifiers)
    }

    public func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof] {
        try await rings.merkleProofs(for: leaves, inTree: tree)
    }

    public func proveTransfer(_ request: IndexedTransferProofRequest) async throws -> IndexedTransferProof {
        try await rings.proveTransfer(request)
    }

    /// Returns whether the provider's server serves a Solana Rings indexer and a prover that the network's policy
    /// attests, whatever capabilities the client declares.
    ///
    /// - Returns: Whether the indexer answers a read and the prover's attestation then passes the network's policy.
    /// - Throws: A rate-limit ``RPCError``, or `CancellationError`.
    public func servesPrivateBalances() async throws -> Bool {
        do {
            _ = try await rings.shieldedTransactions(spending: [[UInt8](repeating: 0, count: 32)])
            _ = try await rings.attestedKey.key()
            return true
        } catch let error as RPCError where error.isRateLimited {
            throw error
        } catch {
            try Task.checkCancellation()
            return false
        }
    }
}
