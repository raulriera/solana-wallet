import ModularArithmetic
@testable import Privacy
import RPC
import Testing
import Transactions

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct PrivateBalanceLiveTests {
    private static let unregistered = "11111111111111111111111111111111"

    @Test
    func `Registry lookups decode every owner's record`() async throws {
        let addresses = try (ShieldedPoolOwners.devnet + [Self.unregistered]).map(Address.init)

        let recipients = try await UserRegistry.recipients(of: addresses, using: Solana(network: .devnet))

        #expect(recipients.map { $0?.signingAddress.value } == ShieldedPoolOwners.devnet + [nil])
    }

    @Test(arguments: ShieldedPoolOwners.devnet)
    func `Deposits rebuild with the registry's owner hash`(owner: String) async throws {
        let address = try Address(owner)
        let records = try await UserRegistry.recipients(of: [address], using: Solana(network: .devnet))
        let recipient = try #require(records.first ?? nil)
        let batch = try await HeliusRPC(apiKey: try LiveClients.heliusAPIKey(), network: .devnet)
            .shieldedTransactions(taggedWith: [address.bytes], after: nil)
        let deposits = batch.transactions.filter(\.isProofless).flatMap(\.outputs).filter { $0.viewTag == address.bytes }
        try #require(!deposits.isEmpty, "The owner must have a deposit")

        let failures = try deposits.flatMap { output in
            let payload = try ProoflessOutput(decoding: output.payload)
            let blinding = ShieldedPool.depositBlinding(tree: try ShieldedPool.tree(id: output.treeID), leafIndex: output.leafIndex)
            let utxo = UTXO(owner: recipient.owner, mint: payload.mint, amount: payload.amount, blinding: blinding, treeID: output.treeID)
            let checks = [
                "owner": payload.owner == recipient.owner,
                "blinding": payload.blinding == blinding,
                "UTXO hash": utxo.hash.bigEndianBytes == output.utxoHash,
                "received UTXO": try ReceivedNote.depositUTXO(in: output, owner: recipient.owner) == utxo,
            ]
            return checks.filter { !$0.value }.map { "leaf \(output.leafIndex) of tree \(output.treeID): \($0.key)" }
        }

        #expect(failures.isEmpty)
    }
}
