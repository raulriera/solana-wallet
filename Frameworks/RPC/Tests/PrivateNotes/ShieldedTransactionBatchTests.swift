import Testing
@testable import RPC

/// Verifies the identity of shielded transaction batches.
struct ShieldedTransactionBatchTests {
    /// Verifies batches with different resume positions or output trees are different.
    ///
    /// - Parameters:
    ///   - outputTreeID: The changed output tree.
    ///   - cursor: The changed resume cursor.
    @Test(arguments: [(UInt16?(1), String?.none), (nil, "AQ==")])
    func `Batches differ by output tree and position`(outputTreeID: UInt16?, cursor: String?) {
        let position = NoteSyncPosition(tags: [[1]], groupCount: 1)
        let base = ShieldedTransactionBatch(transactions: [], outputTreeID: nil, position: position)

        let other = ShieldedTransactionBatch(
            transactions: [], outputTreeID: outputTreeID,
            position: NoteSyncPosition(tags: [[1]], transactionCursors: [cursor], outputCursors: [nil])
        )

        #expect(other != base)
        #expect(ShieldedTransactionBatch(transactions: [], outputTreeID: nil, position: position) == base)
    }
}
