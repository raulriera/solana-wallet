import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
import RPC
import Testing
import Transactions

struct ReceivedNoteTests {
    @Test(arguments: try DepositNoteVectors.load().deposits)
    func `Deposits match the independent reference`(_ vector: DepositNoteVectors.Deposit) throws {
        let transaction = try vector.transaction()

        let notes = try ReceivedNote.notes(in: transaction, of: TransferVectors.sender())

        #expect(notes.map(\.utxo.hash.bigEndianBytes) == (vector.ownedBySender ? [try fixtureBytes(vector.utxoHash)] : []))
        #expect(notes.map(\.nullifier.bigEndianBytes) == (try vector.nullifier.map { [try fixtureBytes($0)] } ?? []))
        #expect(notes.map(\.utxo.amount) == (vector.ownedBySender ? [try #require(UInt64(vector.lamports))] : []))
        #expect(notes.map(\.leafIndex) == (vector.ownedBySender ? [vector.leafIndex] : []))
        #expect(notes.map(\.signature) == (vector.ownedBySender ? ["deposit"] : []))
        #expect(notes.map(\.treeID) == (vector.ownedBySender ? [vector.treeID] : []))
    }

    @Test
    func `Deposits at another position are skipped`() throws {
        let vector = try #require(try DepositNoteVectors.load().deposits.first)

        #expect(try ReceivedNote.notes(in: vector.transaction(leafIndex: vector.leafIndex + 1), of: TransferVectors.sender()).isEmpty)
    }

    @Test
    func `Senders receive their change`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let sender = try TransferVectors.sender()

        let notes = try ReceivedNote.notes(in: PlanFixtures.transaction(of: plan), of: sender)

        let change = try #require(plan.outputs[1].utxo)
        #expect(notes == [ReceivedNote(utxo: change, leafIndex: 41, signature: "transact", slot: 9, nullifier: change.nullifier(using: sender.nullifierKey))])
    }

    @Test
    func `Outputs tagged with the viewing key are received`() throws {
        let record = try #require(try RegistryVectors.load().records.first { $0.owner == TransferVectors.senderSigningAddress })

        let (plan, notes) = try Self.change(taggedWith: Array(try fixtureBytes(record.viewingPublicKey).dropFirst()))

        #expect(notes.map(\.utxo) == [plan.outputs[1].utxo])
    }

    @Test
    func `Outputs tagged for another account aren't received`() throws {
        let (_, notes) = try Self.change(taggedWith: try Address(TransferVectors.recipientSigningAddress).bytes)

        #expect(notes.isEmpty)
    }

    @Test
    func `Padding outputs are skipped`() throws {
        let plan = try PlanFixtures.plan(
            spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: nil, withdrawal: PlanFixtures.withdrawal(lamports: 10), paddingOutputs: 1
        )

        let notes = try ReceivedNote.notes(in: PlanFixtures.transaction(of: plan), of: TransferVectors.sender())

        #expect(notes.map(\.utxo) == [plan.outputs[0].utxo])
    }

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

    @Test(arguments: X25519Fixtures.lowOrderCoordinates)
    func `Transactions under a low-order viewing key yield no notes`(u: [UInt8]) throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let sealed = try PlanFixtures.transaction(of: plan)
        let lowOrder = ShieldedTransaction(
            signature: sealed.signature, slot: sealed.slot, eventIndex: nil, transactionViewingKey: [4] + u, salt: sealed.salt,
            outputs: sealed.outputs, nullifiers: sealed.nullifiers, isProofless: false
        )

        #expect(try ReceivedNote.notes(in: lowOrder, of: TransferVectors.sender()).isEmpty)
    }

    @Test
    func `Note diagnostics omit the values`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let note = try #require(try ReceivedNote.notes(in: PlanFixtures.transaction(of: plan), of: TransferVectors.sender()).first)
        var dumped = ""
        dump(note, to: &dumped)

        #expect(String(reflecting: note) == "ReceivedNote")
        #expect(dumped == "- ReceivedNote\n")
    }

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

    private static func change(taggedWith tag: [UInt8]) throws -> (plan: TransactPlan, notes: [ReceivedNote]) {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let transaction = try PlanFixtures.transaction(of: plan)
        let retagged = ShieldedTransaction(
            signature: transaction.signature, slot: transaction.slot, eventIndex: transaction.eventIndex,
            transactionViewingKey: transaction.transactionViewingKey, salt: transaction.salt,
            outputs: transaction.outputs.map {
                ShieldedOutput(viewTag: tag, utxoHash: $0.utxoHash, treeID: $0.treeID, leafIndex: $0.leafIndex, payload: $0.payload)
            },
            nullifiers: transaction.nullifiers, isProofless: false
        )
        return (plan, try ReceivedNote.notes(in: retagged, of: TransferVectors.sender()))
    }
}
