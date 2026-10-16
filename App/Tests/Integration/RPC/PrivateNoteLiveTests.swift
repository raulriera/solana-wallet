import RPC
import Testing
import Transactions

/// Verifies Helius's Solana Rings indexer on devnet with read-only requests.
///
/// The owners are public devnet addresses with Solana Rings activity, found read-only on 2026-10-16:
/// `getSignaturesForAddress` on the shielded-pool program `sppU489D7A4U1exNo1oeMGZtLEofq3a6o2fR7UeoWB6`
/// at the public devnet RPC, then `getTransaction` on its recent transactions. Each owner paid for a
/// deposit (tag 15) to its own view tag, and the first also sent a transact (tag 16). All four hold
/// 134-byte user-registry records (`getProgramAccounts` on `regyS5rkAcw2YzDJCmTwCTHs2s246FXxbmuRZ42u2PD`).
@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct PrivateNoteLiveTests {
    /// Devnet owners whose Ed25519 public keys are their view tags.
    private static let owners = [
        "FVzg3KzZGudAbj9S7DuvXsryACrL6XSF5gb5FTPpBTZW",
        "7bACPtzxZANLtm8M6E5ovGrftXvcdia9qokkUwWSWBaW",
        "3VtwQ5NpmfWfMusP2P1qENpFyYYFaUyXkbjDyuaiHXva",
        "AHUWkkufV4h1fPNyWAxwrzvTBYUeaGfpa8ygjz8X6vTQ",
    ]

    /// Reads an owner's transactions, checks their structure, and reads again from the returned position.
    ///
    /// - Parameter owner: The owner's base-58 address, whose bytes are its view tag.
    /// - Throws: A credential, provider, decoding, or test prerequisite error.
    @Test(arguments: owners)
    func `Tag reads return an owner's transactions and resume after them`(owner: String) async throws {
        let provider = HeliusRPC(apiKey: try LiveClients.heliusAPIKey(), network: .devnet)
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
        #expect(deposits.allSatisfy { $0.outputs[0].viewTag == tags[0] })
        let confidential = batch.transactions.filter { !$0.isProofless }
        #expect(confidential.allSatisfy { $0.transactionViewingKey?.count == 33 && $0.salt?.count == 16 })

        let later = try await provider.shieldedTransactions(taggedWith: tags, after: batch.position)

        #expect(Set(later.transactions.map(\.signature)).isDisjoint(with: batch.transactions.map(\.signature)))
    }

    /// Reads the transactions that spent the nullifiers of the owners' confidential transactions.
    ///
    /// - Throws: A credential, provider, decoding, or test prerequisite error.
    @Test
    func `Nullifier reads return the transactions that spent them`() async throws {
        let provider = HeliusRPC(apiKey: try LiveClients.heliusAPIKey(), network: .devnet)
        let batch = try await provider.shieldedTransactions(taggedWith: try Self.owners.map { try Address($0).bytes },
                                                            after: nil)
        let spenders = batch.transactions.filter { !$0.nullifiers.isEmpty }
        try #require(!spenders.isEmpty, "The owners must have a confidential transaction")
        let nullifiers = Set(spenders.flatMap(\.nullifiers))

        let spending = try await provider.shieldedTransactions(spending: Array(nullifiers))

        #expect(Set(spenders.map(\.signature)).isSubset(of: spending.map(\.signature)))
        #expect(spending.allSatisfy { !nullifiers.isDisjoint(with: $0.nullifiers) })
    }
}
