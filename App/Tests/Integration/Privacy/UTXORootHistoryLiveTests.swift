import ModularArithmetic
import RPC
import Testing
@testable import Privacy

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct UTXORootHistoryLiveTests {
    @Test(arguments: ShieldedPoolOwners.devnet)
    func `An owner's received deposits are in their trees under on-chain roots`(owner: String) async throws {
        let (recipient, deposits) = try await ShieldedPoolOwners.deposits(of: owner)
        let notes = try deposits.compactMap { deposit in
            let output = try #require(deposit.outputs.first)
            return try ReceivedNote.depositUTXO(in: output, owner: recipient.owner).map { utxo in
                ReceivedNote(utxo: utxo, leafIndex: output.leafIndex, signature: deposit.signature, slot: deposit.slot, nullifier: .zero)
            }
        }
        try #require(!notes.isEmpty, "The owner must have a received deposit")

        let statuses = try await ReceivedNote.inclusionStatuses(of: notes, rpc: SolanaRPC(network: .devnet),
                                                                indexer: Zolana(network: .devnet))

        #expect(statuses == Array(repeating: .included, count: notes.count))
    }
}
