import CryptoKit
import ModularArithmetic
import RPC
import Transactions

/// A UTXO that an account received, where the indexer saw it, and the nullifier that spends it.
///
/// An account finds its notes in the shielded transactions that the indexer returns for its tags:
///
/// - In a confidential transaction, each output whose view tag is the account's signing address is
///   opened with the account's viewing key and the transaction's viewing key and salt, at the
///   output's position. The UTXO is the account's only if the note decodes and its rebuilt hash is
///   the published one.
/// - In a proofless deposit, the output publishes the UTXO in the clear. The UTXO is the account's
///   only if it holds SOL for the account's owner hash, its blinding is the one that the program
///   derives from the tree and the leaf index, and its rebuilt hash is the published one.
///
/// Outputs that don't pass are someone else's, not errors. A note is spent once the indexer
/// returns a transaction that publishes its nullifier. Descriptions and reflection omit the values.
struct ReceivedNote: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The received UTXO.
    let utxo: UTXO

    /// The UTXO's position in its tree.
    let leafIndex: UInt64

    /// The signature of the transaction that created the UTXO.
    let signature: String

    /// The slot of the transaction that created the UTXO.
    let slot: UInt64

    /// The nullifier that spending the UTXO publishes.
    let nullifier: Poseidon.Element

    /// A description that omits the values.
    var description: String { "ReceivedNote" }

    /// A debugging description that omits the values.
    var debugDescription: String { description }

    /// A reflection view that omits the values.
    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Finds an account's notes in a shielded transaction.
    ///
    /// - Parameters:
    ///   - transaction: A transaction that the indexer returned for the account's tags.
    ///   - account: The account's signing address, nullifier key, and viewing key.
    /// - Returns: The account's notes, in output order; empty if none of the outputs is the account's.
    /// - Throws: ``SlotCipher/CipherError/cryptorFailed`` if CommonCrypto fails, or a CryptoKit
    ///   error if the key agreement fails.
    static func notes(in transaction: ShieldedTransaction, of account: TransactPlan.Sender) throws -> [ReceivedNote] {
        let owner = OwnerIdentity.ownerHash(signingPublicKey: account.signingAddress.bytes, nullifierPublicKey: account.nullifierKey.publicKey)
        let utxos = try transaction.isProofless
            ? deposits(in: transaction, owner: owner)
            : confidentialUTXOs(in: transaction, of: account, owner: owner)
        return utxos.map { output, utxo in
            ReceivedNote(
                utxo: utxo, leafIndex: output.leafIndex, signature: transaction.signature, slot: transaction.slot,
                nullifier: utxo.nullifier(using: account.nullifierKey)
            )
        }
    }

    /// Opens the confidential outputs tagged with the account's signing address.
    ///
    /// - Parameters:
    ///   - transaction: A confidential transaction.
    ///   - account: The account.
    ///   - owner: The account's owner hash.
    /// - Returns: Each output that the account received, with its UTXO.
    /// - Throws: A cipher or key agreement error.
    private static func confidentialUTXOs(
        in transaction: ShieldedTransaction,
        of account: TransactPlan.Sender,
        owner: Poseidon.Element
    ) throws -> [(ShieldedOutput, UTXO)] {
        // A transaction without a valid viewing key or salt carries no note that the account can open.
        guard let viewingKeyBytes = transaction.transactionViewingKey, let salt = transaction.salt,
              let transactionViewingPublicKey = try? P256.KeyAgreement.PublicKey(compressedRepresentation: viewingKeyBytes) else {
            return []
        }
        return try transaction.outputs.enumerated().compactMap { index, output in
            guard output.viewTag == account.signingAddress.bytes,
                  let payload = try? ConfidentialOutput(decoding: output.payload),
                  let utxoHash = Poseidon.Element(bigEndianBytes: output.utxoHash),
                  let utxo = try payload.receive(
                      viewingKey: account.viewingKey, owner: owner, transactionViewingPublicKey: transactionViewingPublicKey,
                      salt: salt, slot: UInt32(index), treeID: output.treeID, utxoHash: utxoHash
                  ) else { return nil }
            return (output, utxo)
        }
    }

    /// Rebuilds the proofless deposits that belong to an owner hash.
    ///
    /// - Parameters:
    ///   - transaction: A proofless deposit.
    ///   - owner: The account's owner hash.
    /// - Returns: Each output that the account received, with its UTXO.
    /// - Throws: A ``Transactions/ValidationError`` if a tree account's derivation fails, which
    ///   doesn't happen.
    private static func deposits(in transaction: ShieldedTransaction, owner: Poseidon.Element) throws -> [(ShieldedOutput, UTXO)] {
        try transaction.outputs.compactMap { output in try depositUTXO(in: output, owner: owner).map { (output, $0) } }
    }

    /// Rebuilds a proofless deposit's UTXO if it belongs to an owner hash.
    ///
    /// The check needs only public values: the owner hash comes from the owner's registry record or
    /// keys.
    ///
    /// - Parameters:
    ///   - output: A proofless deposit's output.
    ///   - owner: The owner hash.
    /// - Returns: The UTXO, or `nil` if the payload isn't a SOL deposit for `owner` with the
    ///   program's blinding for the output's position and the published hash.
    /// - Throws: A ``Transactions/ValidationError`` if the tree account's derivation fails, which
    ///   doesn't happen.
    static func depositUTXO(in output: ShieldedOutput, owner: Poseidon.Element) throws -> UTXO? {
        guard let deposit = try? ProoflessOutput(decoding: output.payload),
              deposit.owner == owner, deposit.mint == ConfidentialPlaintext.Asset.sol.mint,
              deposit.blinding == ShieldedPool.depositBlinding(tree: try ShieldedPool.tree(id: output.treeID), leafIndex: output.leafIndex),
              let utxoHash = Poseidon.Element(bigEndianBytes: output.utxoHash) else { return nil }
        let utxo = UTXO(owner: owner, mint: deposit.mint, amount: deposit.amount, blinding: deposit.blinding, treeID: output.treeID)
        return utxo.hash == utxoHash ? utxo : nil
    }
}
