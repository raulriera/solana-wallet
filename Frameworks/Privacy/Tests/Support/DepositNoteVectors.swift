import ModularArithmetic
@testable import Privacy
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

        private static let mintRange = 70..<102

        func transaction(
            leafIndex: UInt64? = nil, signature: String = "deposit", slot: UInt64 = 3, mint: [UInt8]? = nil
        ) throws -> ShieldedTransaction {
            var (payload, utxoHash) = (try fixtureBytes(payload), try fixtureBytes(utxoHash))
            if let mint {
                payload.replaceSubrange(Self.mintRange, with: mint)
                let deposit = try ProoflessOutput(decoding: payload)
                utxoHash = UTXO(owner: deposit.owner, mint: mint, amount: deposit.amount, blinding: deposit.blinding, treeID: treeID)
                    .hash.bigEndianBytes
            }
            let output = ShieldedOutput(
                viewTag: try Address(TransferVectors.senderSigningAddress).bytes, utxoHash: utxoHash, treeID: treeID,
                leafIndex: leafIndex ?? self.leafIndex, payload: payload
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
