extension HeliusRPC: PrivateNoteProviding {
    public func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch {
        try await zolana.shieldedTransactions(taggedWith: tags, after: position)
    }

    public func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction] {
        try await zolana.shieldedTransactions(spending: nullifiers)
    }
}
