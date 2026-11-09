import RPC
import Testing
import Transactions
@testable import Privacy

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct SpentNullifiersLiveTests {
    @Test
    func `Finalized private transacts and merges spend the nullifiers that the indexer reports`() async throws {
        let owner = try Address(ShieldedPoolOwners.devnet[0])
        let batch = try await Zolana(network: .devnet).shieldedTransactions(taggedWith: [owner.bytes], after: nil)
        let spends = batch.transactions.filter { !$0.isProofless && !$0.nullifiers.isEmpty }.prefix(4)
        try #require(!spends.isEmpty, "The owner must have a finalized spend")
        let rpc = SolanaRPC(network: .devnet)
        var tags = Set<UInt8>()

        for spend in spends {
            let transaction = try #require(try await rpc.send(GetTransaction(signature: spend.signature)))
            tags.formUnion(transaction.instructionData(invoking: ShieldedPool.programID).compactMap(\.first))

            #expect(transaction.error == nil)
            #expect(try ShieldedPool.nullifiers(spentBy: transaction) == Set(spend.nullifiers))
        }

        #expect(tags.isSuperset(of: [ShieldedPool.transactTag, ShieldedPool.mergeTransactTag]))
    }
}
