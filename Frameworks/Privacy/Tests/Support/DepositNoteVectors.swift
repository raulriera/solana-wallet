import RPC
import Testing
import Transactions

struct DepositNoteVectors: Decodable, Sendable {
    let deposits: [Deposit]

    struct Deposit: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let ownedBySender: Bool
        let treeID: UInt16
        let leafIndex: UInt64
        let lamports: String
        let payload: String
        let utxoHash: String
        let blinding: String
        let nullifier: String?

        var testDescription: String { name }

        func transaction(leafIndex: UInt64? = nil, signature: String = "deposit", slot: UInt64 = 3) throws -> ShieldedTransaction {
            let output = ShieldedOutput(
                viewTag: try Address(TransferVectors.senderSigningAddress).bytes, utxoHash: try fixtureBytes(utxoHash), treeID: treeID,
                leafIndex: leafIndex ?? self.leafIndex, payload: try fixtureBytes(payload)
            )
            return ShieldedTransaction(
                signature: signature, slot: slot, eventIndex: 0, transactionViewingKey: nil, salt: nil, outputs: [output],
                nullifiers: [], isProofless: true
            )
        }
    }

    static func load() throws -> Self {
        try fixture(named: "DepositNoteVectors")
    }
}
