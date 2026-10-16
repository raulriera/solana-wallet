import RPC
import Testing
import Transactions

/// Proofless deposit outputs computed by an independent Python implementation written from zolana
/// v0.4.0-alpha's sources.
///
/// Three deposits belong to the sender of zolana's published transfers, with no memo, a memo, and
/// an empty memo with the largest amount; one belongs to the recipient. Each output's blinding is
/// the program's derivation from its tree and leaf index. Bytes and field elements are
/// hexadecimal.
struct DepositNoteVectors: Decodable, Sendable {
    /// The deposits.
    let deposits: [Deposit]

    /// A deposit's output and the note it holds.
    struct Deposit: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name.
        let name: String
        /// Whether the sender owns the UTXO.
        let ownedBySender: Bool
        /// The ID of the tree that holds the UTXO.
        let treeID: UInt16
        /// The UTXO's position in the tree.
        let leafIndex: UInt64
        /// The amount, as a decimal integer, since it may exceed a JSON number's precision.
        let lamports: String
        /// The output's payload.
        let payload: String
        /// The UTXO's hash.
        let utxoHash: String
        /// The UTXO's blinding.
        let blinding: String
        /// The sender's nullifier of the UTXO, or `nil` for another owner's UTXO.
        let nullifier: String?

        /// The vector's name, in test results.
        var testDescription: String { name }

        /// Creates the indexer's view of the deposit: a proofless transaction with its one output,
        /// tagged with the sender.
        ///
        /// - Parameters:
        ///   - leafIndex: The position that the indexer reports, or `nil` for the deposit's own.
        ///   - signature: The transaction's signature.
        ///   - slot: The transaction's slot.
        /// - Returns: The transaction.
        /// - Throws: A test failure if the vector is malformed.
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

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The deposit vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "DepositNoteVectors")
    }
}
