import ModularArithmetic
@testable import Privacy
import RPC
import Testing
import Transactions

/// Verifies Solana Rings registry records and deposits of real devnet owners with read-only requests.
///
/// The owners are ``ShieldedPoolOwners``: each holds a user-registry record and paid for a proofless
/// deposit to its own view tag. Registry records come from the public
/// devnet RPC, which serves every wallet; deposits come from Helius's indexer.
@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct PrivateBalanceLiveTests {
    /// An address without a registry record: the System Program.
    private static let unregistered = "11111111111111111111111111111111"

    /// Reads every owner's record and an unregistered address's with one public devnet request.
    ///
    /// - Throws: A provider, validation, or test prerequisite error.
    @Test
    func `Registry lookups decode every owner's record`() async throws {
        let addresses = try (ShieldedPoolOwners.devnet + [Self.unregistered]).map(Address.init)

        let recipients = try await UserRegistry.recipients(of: addresses, using: Solana(network: .devnet))

        #expect(recipients.map { $0?.signingAddress.value } == ShieldedPoolOwners.devnet + [nil])
    }

    /// Checks each proofless deposit tagged with an owner against the owner's registry record: the
    /// payload decodes, its blinding is the program's for the output's position, and the UTXO
    /// rebuilt with the registry's owner hash is the published one.
    ///
    /// - Parameter owner: The owner's base-58 address, whose bytes are its view tag.
    /// - Throws: A credential, provider, validation, or test prerequisite error.
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
