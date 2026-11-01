extension HeliusRPC: PrivateNoteProviding {
    public func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch {
        try await zolana.shieldedTransactions(taggedWith: tags, after: position)
    }

    public func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction] {
        try await zolana.shieldedTransactions(spending: nullifiers)
    }

    public func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof] {
        try await zolana.merkleProofs(for: leaves, inTree: tree)
    }

    public func nonInclusionProofs(for nullifiers: [[UInt8]], inTree tree: String) async throws -> [NonInclusionProof] {
        try await zolana.nonInclusionProofs(for: nullifiers, inTree: tree)
    }
}
