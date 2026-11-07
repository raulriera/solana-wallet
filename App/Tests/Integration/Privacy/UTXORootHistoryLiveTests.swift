import ModularArithmetic
import RPC
import Testing
@testable import Privacy

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct UTXORootHistoryLiveTests {
    @Test(arguments: ShieldedPoolOwners.devnet)
    func `An owner's received deposits are in their trees under on-chain roots`(owner: String) async throws {
        let (recipient, deposits) = try await ShieldedPoolOwners.deposits(of: owner)
        let notes = try deposits.map { deposit in
            let output = try #require(deposit.outputs.first)
            let utxo = try #require(try ReceivedNote.depositUTXO(in: output, owner: recipient.owner))
            return ReceivedNote(utxo: utxo, leafIndex: output.leafIndex, signature: deposit.signature, slot: deposit.slot,
                                nullifier: .zero)
        }

        let statuses = try await ReceivedNote.inclusionStatuses(of: notes, rpc: SolanaRPC(network: .devnet),
                                                                indexer: Zolana(network: .devnet))

        #expect(statuses == Array(repeating: .included, count: notes.count))
    }
}
