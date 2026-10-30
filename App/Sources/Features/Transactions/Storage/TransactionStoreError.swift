/// An error for a transaction store request that can't be served.
nonisolated enum TransactionStoreError: Error {
    case missingRecord
}
