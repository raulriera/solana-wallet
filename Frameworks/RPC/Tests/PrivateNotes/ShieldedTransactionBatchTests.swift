import Testing
@testable import RPC

struct ShieldedTransactionBatchTests {
    @Test(arguments: [(UInt16?(1), String?.none, false), (nil, "AQ==", false), (nil, nil, true)])
    func `Batches differ by output tree, position, and whether more come`(
        outputTreeID: UInt16?, cursor: String?, moreComing: Bool
    ) {
        let position = NoteSyncPosition(tags: [[1]], groupCount: 1)
        let base = ShieldedTransactionBatch(transactions: [], outputTreeID: nil, position: position, moreComing: false)
        let same = ShieldedTransactionBatch(transactions: [], outputTreeID: nil, position: position, moreComing: false)

        let other = ShieldedTransactionBatch(
            transactions: [], outputTreeID: outputTreeID,
            position: NoteSyncPosition(tags: [[1]], transactionCursors: [cursor], outputCursors: [nil]),
            moreComing: moreComing
        )

        #expect(other != base)
        #expect(same == base)
    }
}
