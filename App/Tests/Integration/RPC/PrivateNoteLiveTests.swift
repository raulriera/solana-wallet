import RPC
import Testing
import Transactions

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct PrivateNoteLiveTests {
    @Test(arguments: ShieldedPoolOwners.devnet)
    func `Tag reads return an owner's transactions and resume after them`(owner: String) async throws {
        let provider = Zolana(network: .devnet)
        let tags = [try Address(owner).bytes]

        let batch = try await provider.shieldedTransactions(taggedWith: tags, after: nil)

        #expect(!batch.transactions.isEmpty)
        #expect(batch.outputTreeID != nil)
        let outputs = batch.transactions.flatMap(\.outputs)
        #expect(outputs.allSatisfy { $0.viewTag.count == 32 && $0.utxoHash.count == 32 })
        #expect(batch.transactions.flatMap(\.nullifiers).allSatisfy { $0.count == 32 })
        let deposits = batch.transactions.filter(\.isProofless)
        #expect(deposits.allSatisfy {
            $0.outputs.count == 1 && $0.transactionViewingKey == nil && $0.salt == nil && $0.nullifiers.isEmpty
        })
        #expect(deposits.allSatisfy { $0.outputs[0].viewTag == tags[0] && $0.outputs[0].payload.first == 0 })
        let confidential = batch.transactions.filter { !$0.isProofless }
        #expect(confidential.allSatisfy {
            [[33, 16], [nil, nil]].contains([$0.transactionViewingKey?.count, $0.salt?.count])
        })

        let later = try await provider.shieldedTransactions(taggedWith: tags, after: batch.position)

        #expect(Set(later.transactions.map(\.signature)).isDisjoint(with: batch.transactions.map(\.signature)))
    }

    @Test
    func `Nullifier reads return the transactions that spent them`() async throws {
        let provider = Zolana(network: .devnet)
        let batch = try await provider.shieldedTransactions(taggedWith: try ShieldedPoolOwners.devnet.map { try Address($0).bytes },
                                                            after: nil)
        let spenders = batch.transactions.filter { !$0.nullifiers.isEmpty }
        try #require(!spenders.isEmpty, "The owners must have a confidential transaction")
        let nullifiers = Set(spenders.flatMap(\.nullifiers))

        let spending = try await provider.shieldedTransactions(spending: Array(nullifiers))

        #expect(Set(spenders.map(\.signature)).isSubset(of: spending.map(\.signature)))
        #expect(spending.allSatisfy { !nullifiers.isDisjoint(with: $0.nullifiers) })
    }

    @Test(arguments: [Network.mainnet, .devnet])
    func `Reads of a random value find nothing`(network: Network) async throws {
        let provider = Zolana(network: network)
        let value = randomFieldElement()

        async let taggedRead = provider.shieldedTransactions(taggedWith: [value], after: nil)
        async let spendingRead = provider.shieldedTransactions(spending: [value])
        let (tagged, spending) = try await (taggedRead, spendingRead)

        #expect(tagged.transactions.isEmpty)
        #expect(spending.isEmpty)
    }
}
