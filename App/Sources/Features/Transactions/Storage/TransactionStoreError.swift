/// A transaction store request that can't be served.
nonisolated enum TransactionStoreError: Error {
    /// The record to watch isn't kept, such as after a reset.
    case missingRecord
}
