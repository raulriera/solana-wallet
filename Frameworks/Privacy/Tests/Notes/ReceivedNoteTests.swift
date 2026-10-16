import CryptoKit
import ModularArithmetic
@testable import Privacy
import RPC
import Testing
import Transactions

/// Verifies that an account finds its notes in the indexer's transactions: proofless deposits
/// against an independent implementation, and the outputs of transact plans.
struct ReceivedNoteTests {
    /// Verifies that the sender receives its deposits with their nullifiers, and not another
    /// owner's deposit.
    ///
    /// - Parameter vector: A deposit.
    @Test(arguments: try DepositNoteVectors.load().deposits)
    func `Deposits match the independent reference`(_ vector: DepositNoteVectors.Deposit) throws {
        let transaction = try Self.deposit(vector, leafIndex: vector.leafIndex)

        let notes = try ReceivedNote.notes(in: transaction, of: TransferVectors.sender())

        #expect(notes.map(\.utxo.hash.bigEndianBytes) == (vector.ownedBySender ? [try fixtureBytes(vector.utxoHash)] : []))
        #expect(notes.map(\.nullifier.bigEndianBytes) == (try vector.nullifier.map { [try fixtureBytes($0)] } ?? []))
        #expect(notes.map(\.utxo.amount) == (vector.ownedBySender ? [try #require(UInt64(vector.lamports))] : []))
        #expect(notes.map(\.leafIndex) == (vector.ownedBySender ? [vector.leafIndex] : []))
        #expect(notes.map(\.signature) == (vector.ownedBySender ? ["deposit"] : []))
    }

    /// Verifies that a deposit reported at another leaf isn't received, because its blinding isn't
    /// the program's for that position.
    @Test
    func `Deposits at another position are skipped`() throws {
        let vector = try #require(try DepositNoteVectors.load().deposits.first)

        #expect(try ReceivedNote.notes(in: Self.deposit(vector, leafIndex: vector.leafIndex + 1), of: TransferVectors.sender()).isEmpty)
    }

    /// Verifies that the sender receives its change from a transfer, at the output's position,
    /// and not the recipient's output.
    @Test
    func `Senders receive their change`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let sender = try TransferVectors.sender()

        let notes = try ReceivedNote.notes(in: Self.transaction(of: plan, salt: TransferVectors.salt), of: sender)

        let change = try #require(plan.outputs[1].utxo)
        #expect(notes == [ReceivedNote(utxo: change, leafIndex: 41, signature: "transact", slot: 9, nullifier: change.nullifier(using: sender.nullifierKey))])
    }

    /// Verifies that a padding output tagged with the sender's view tag isn't received, while the
    /// sender's zero-amount output is.
    @Test
    func `Padding outputs are skipped`() throws {
        let plan = try PlanFixtures.plan(
            spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: nil, withdrawal: PlanFixtures.withdrawal(lamports: 10), paddingOutputs: 1
        )

        let notes = try ReceivedNote.notes(in: Self.transaction(of: plan, salt: TransferVectors.salt), of: TransferVectors.sender())

        #expect(notes.map(\.utxo) == [plan.outputs[0].utxo])
    }

    /// Verifies that notes sealed under another salt, or a transaction without a viewing key,
    /// yield nothing.
    @Test
    func `Unreadable transactions yield no notes`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let sender = try TransferVectors.sender()
        let sealed = try Self.transaction(of: plan, salt: TransferVectors.salt)
        let withoutKey = ShieldedTransaction(
            signature: sealed.signature, slot: sealed.slot, eventIndex: nil, transactionViewingKey: nil, salt: sealed.salt,
            outputs: sealed.outputs, nullifiers: sealed.nullifiers, isProofless: false
        )

        #expect(try ReceivedNote.notes(in: Self.transaction(of: plan, salt: [UInt8](repeating: 0x5b, count: 16)), of: sender).isEmpty)
        #expect(try ReceivedNote.notes(in: withoutKey, of: sender).isEmpty)
    }

    /// Verifies that printing, dumping, and reflecting a note omit its values.
    @Test
    func `Note diagnostics omit the values`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let note = try #require(try ReceivedNote.notes(in: Self.transaction(of: plan, salt: TransferVectors.salt), of: TransferVectors.sender()).first)
        var dumped = ""
        dump(note, to: &dumped)

        #expect(String(reflecting: note) == "ReceivedNote")
        #expect(dumped == "- ReceivedNote\n")
    }

    /// Creates the indexer's view of a deposit vector.
    ///
    /// - Parameters:
    ///   - vector: The deposit.
    ///   - leafIndex: The position that the indexer reports.
    /// - Returns: A proofless transaction with the deposit's one output.
    /// - Throws: A test failure if the vector is malformed.
    private static func deposit(_ vector: DepositNoteVectors.Deposit, leafIndex: UInt64) throws -> ShieldedTransaction {
        let output = ShieldedOutput(
            viewTag: try Address(TransferVectors.senderSigningAddress).bytes, utxoHash: try fixtureBytes(vector.utxoHash), treeID: vector.treeID,
            leafIndex: leafIndex, payload: try fixtureBytes(vector.payload)
        )
        return ShieldedTransaction(
            signature: "deposit", slot: 3, eventIndex: 0, transactionViewingKey: nil, salt: nil, outputs: [output], nullifiers: [],
            isProofless: true
        )
    }

    /// Creates the indexer's view of a plan's transact, with output i at leaf 40 + i.
    ///
    /// - Parameters:
    ///   - plan: The plan.
    ///   - salt: The salt that the transaction publishes.
    /// - Returns: The transaction.
    /// - Throws: An error if the transaction viewing key can't be derived.
    private static func transaction(of plan: TransactPlan, salt: [UInt8]) throws -> ShieldedTransaction {
        let firstNullifier = try #require(plan.nullifiers.first)
        let viewingKey = try TransactionViewingKey.derive(viewingKey: TransferVectors.sender().viewingKey, firstNullifier: firstNullifier)
        let outputs = plan.outputs.enumerated().map { index, output in
            let viewTag = switch output.published.ownerTag {
            case .inline(let tag): tag
            case .payer: plan.payer.bytes
            }
            return ShieldedOutput(
                viewTag: viewTag, utxoHash: output.published.utxoHash.bigEndianBytes, treeID: plan.outputTreeID,
                leafIndex: 40 + UInt64(index), payload: output.published.data
            )
        }
        return ShieldedTransaction(
            signature: "transact", slot: 9, eventIndex: 0, transactionViewingKey: Array(viewingKey.publicKey.compressedRepresentation),
            salt: salt, outputs: outputs, nullifiers: plan.nullifiers.map(\.bigEndianBytes), isProofless: false
        )
    }
}
