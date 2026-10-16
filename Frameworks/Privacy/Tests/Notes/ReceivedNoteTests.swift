import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
import RPC
import Testing
import Transactions

/// Verifies that an account finds its notes in the indexer's transactions, proofless deposits
/// against an independent implementation and the outputs of transact plans, and the notes' encoding.
struct ReceivedNoteTests {
    /// Verifies that the sender receives its deposits with their nullifiers, and not another
    /// owner's deposit.
    ///
    /// - Parameter vector: A deposit.
    @Test(arguments: try DepositNoteVectors.load().deposits)
    func `Deposits match the independent reference`(_ vector: DepositNoteVectors.Deposit) throws {
        let transaction = try vector.transaction()

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

        #expect(try ReceivedNote.notes(in: vector.transaction(leafIndex: vector.leafIndex + 1), of: TransferVectors.sender()).isEmpty)
    }

    /// Verifies that the sender receives its change from a transfer, at the output's position,
    /// and not the recipient's output.
    @Test
    func `Senders receive their change`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let sender = try TransferVectors.sender()

        let notes = try ReceivedNote.notes(in: PlanFixtures.transaction(of: plan), of: sender)

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

        let notes = try ReceivedNote.notes(in: PlanFixtures.transaction(of: plan), of: TransferVectors.sender())

        #expect(notes.map(\.utxo) == [plan.outputs[0].utxo])
    }

    /// Verifies that notes sealed under another salt, or a transaction without a viewing key,
    /// yield nothing.
    @Test
    func `Unreadable transactions yield no notes`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let sender = try TransferVectors.sender()
        let sealed = try PlanFixtures.transaction(of: plan)
        let withoutKey = ShieldedTransaction(
            signature: sealed.signature, slot: sealed.slot, eventIndex: nil, transactionViewingKey: nil, salt: sealed.salt,
            outputs: sealed.outputs, nullifiers: sealed.nullifiers, isProofless: false
        )

        #expect(try ReceivedNote.notes(in: PlanFixtures.transaction(of: plan, salt: [UInt8](repeating: 0x5b, count: 16)), of: sender).isEmpty)
        #expect(try ReceivedNote.notes(in: withoutKey, of: sender).isEmpty)
    }

    /// Verifies that printing, dumping, and reflecting a note omit its values.
    @Test
    func `Note diagnostics omit the values`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let note = try #require(try ReceivedNote.notes(in: PlanFixtures.transaction(of: plan), of: TransferVectors.sender()).first)
        var dumped = ""
        dump(note, to: &dumped)

        #expect(String(reflecting: note) == "ReceivedNote")
        #expect(dumped == "- ReceivedNote\n")
    }

    /// Verifies that a deposit's note and a transact's note decode to themselves.
    @Test
    func `Notes survive encoding`() throws {
        let sender = try TransferVectors.sender()
        let deposit = try #require(try DepositNoteVectors.load().deposits.first)
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let notes = try ReceivedNote.notes(in: deposit.transaction(), of: sender) + ReceivedNote.notes(in: PlanFixtures.transaction(of: plan), of: sender)

        let decoded = try JSONDecoder().decode([ReceivedNote].self, from: JSONEncoder().encode(notes))

        #expect(notes.count == 2)
        #expect(decoded == notes)
    }

    /// Verifies that an encoded note whose mint or field element has another length, whose field
    /// element isn't canonical, or whose mint isn't SOL's is rejected as corrupted data at that field.
    ///
    /// - Parameters:
    ///   - key: The encoded field to replace.
    ///   - bytes: The replacement.
    @Test(arguments: [
        ("owner", [UInt8](repeating: 0xff, count: 32)),
        ("blinding", [UInt8](repeating: 0, count: 31)),
        ("nullifier", [UInt8](repeating: 0, count: 33)),
        ("mint", [UInt8](repeating: 0, count: 31)),
        ("mint", [UInt8](repeating: 0, count: 31) + [1]),
    ])
    func `Encoded notes with invalid fields are rejected`(key: String, bytes: [UInt8]) throws {
        let deposit = try #require(try DepositNoteVectors.load().deposits.first)
        let note = try #require(try ReceivedNote.notes(in: deposit.transaction(), of: TransferVectors.sender()).first)
        var fields = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any])
        fields[key] = Data(bytes).base64EncodedString()
        let encoded = try JSONSerialization.data(withJSONObject: fields)

        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ReceivedNote.self, from: encoded)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected corrupted data, not \(String(describing: error)).")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == [key])
    }
}
