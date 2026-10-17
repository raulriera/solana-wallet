import CryptoKit
import Foundation
import ModularArithmetic
import RPC
import Transactions

/// A UTXO that an account received, where the indexer saw it, and the nullifier that spends it.
///
/// An account finds its notes in the shielded transactions that the indexer returns for its tags:
///
/// - In a confidential transaction, each output whose view tag is one of the account's view tags,
///   its signing address or its viewing public key's x-coordinate, is opened with the account's
///   viewing key and the transaction's viewing key and salt, at the
///   output's position. The UTXO is the account's only if the note decodes and its rebuilt hash is
///   the published one.
/// - In a proofless deposit, the output publishes the UTXO in the clear. The UTXO is the account's
///   only if it holds SOL for the account's owner hash, its blinding is the one that the program
///   derives from the tree and the leaf index, and its rebuilt hash is the published one.
///
/// Outputs that don't pass are someone else's, not errors. A note is spent once the indexer
/// returns a transaction that publishes its nullifier. Only SOL notes are received.
///
/// A note encodes its UTXO's fields, its position, its transaction, and its nullifier, with field
/// elements and the mint as 32 big-endian bytes; decoding rejects other lengths, non-canonical
/// field elements, and mints other than SOL's. Descriptions and reflection omit the values.
public struct ReceivedNote: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The encoded fields of a note.
    private enum CodingKeys: String, CodingKey {
        case owner, mint, amount, blinding, treeID, leafIndex, signature, slot, nullifier
    }

    /// The received UTXO.
    let utxo: UTXO

    /// The UTXO's position in its tree.
    let leafIndex: UInt64

    /// The signature of the transaction that created the UTXO.
    public let signature: String

    /// The slot of the transaction that created the UTXO.
    public let slot: UInt64

    /// The nullifier that spending the UTXO publishes.
    let nullifier: Poseidon.Element

    /// The note's amount, in lamports.
    public var lamports: UInt64 { utxo.amount }

    /// A description that omits the values.
    public var description: String { "ReceivedNote" }

    /// A debugging description that omits the values.
    public var debugDescription: String { description }

    /// A reflection view that omits the values.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates a note from its parts.
    ///
    /// - Parameters:
    ///   - utxo: The received UTXO.
    ///   - leafIndex: The UTXO's position in its tree.
    ///   - signature: The signature of the transaction that created the UTXO.
    ///   - slot: The slot of the transaction that created the UTXO.
    ///   - nullifier: The nullifier that spending the UTXO publishes.
    init(utxo: UTXO, leafIndex: UInt64, signature: String, slot: UInt64, nullifier: Poseidon.Element) {
        self.utxo = utxo
        self.leafIndex = leafIndex
        self.signature = signature
        self.slot = slot
        self.nullifier = nullifier
    }

    /// Decodes a note and checks the lengths and canonical encoding of its fields.
    ///
    /// - Parameter decoder: The decoder that supplies the note's fields.
    /// - Throws: A decoding error for a missing field, a mint that isn't SOL's, or a field element
    ///   that isn't 32 canonical big-endian bytes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mint = [UInt8](try container.decode(Data.self, forKey: .mint))
        guard mint == ConfidentialPlaintext.Asset.sol.mint else {
            throw DecodingError.dataCorruptedError(forKey: .mint, in: container, debugDescription: "A note holds SOL.")
        }
        utxo = UTXO(
            owner: try Self.decodeElement(forKey: .owner, in: container), mint: mint,
            amount: try container.decode(UInt64.self, forKey: .amount), blinding: try Self.decodeElement(forKey: .blinding, in: container),
            treeID: try container.decode(UInt16.self, forKey: .treeID)
        )
        leafIndex = try container.decode(UInt64.self, forKey: .leafIndex)
        signature = try container.decode(String.self, forKey: .signature)
        slot = try container.decode(UInt64.self, forKey: .slot)
        nullifier = try Self.decodeElement(forKey: .nullifier, in: container)
    }

    /// Encodes the note's fields, with field elements and the mint as 32 big-endian bytes.
    ///
    /// - Parameter encoder: The encoder that receives the note's fields.
    /// - Throws: An encoding error if a field can't be written.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Data(utxo.owner.bigEndianBytes), forKey: .owner)
        try container.encode(Data(utxo.mint), forKey: .mint)
        try container.encode(utxo.amount, forKey: .amount)
        try container.encode(Data(utxo.blinding.bigEndianBytes), forKey: .blinding)
        try container.encode(utxo.treeID, forKey: .treeID)
        try container.encode(leafIndex, forKey: .leafIndex)
        try container.encode(signature, forKey: .signature)
        try container.encode(slot, forKey: .slot)
        try container.encode(Data(nullifier.bigEndianBytes), forKey: .nullifier)
    }

    /// Decodes a field element from 32 canonical big-endian bytes.
    ///
    /// - Parameters:
    ///   - key: The field's key.
    ///   - container: The note's container.
    /// - Returns: The field element.
    /// - Throws: A decoding error for a missing field, another length, or a value at or above r.
    private static func decodeElement(
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Poseidon.Element {
        guard let element = Poseidon.Element(bigEndianBytes: [UInt8](try container.decode(Data.self, forKey: key))) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Invalid field element.")
        }
        return element
    }

    /// Finds an account's notes in a shielded transaction.
    ///
    /// - Parameters:
    ///   - transaction: A transaction that the indexer returned for the account's tags.
    ///   - account: The account.
    /// - Returns: The account's notes, in output order; empty if none of the outputs is the account's.
    /// - Throws: ``SlotCipher/CipherError/cryptorFailed`` if CommonCrypto fails, or a CryptoKit
    ///   error if the key agreement fails.
    static func notes(in transaction: ShieldedTransaction, of account: ShieldedAccount) throws -> [ReceivedNote] {
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

    /// Opens the confidential outputs tagged with one of the account's view tags.
    ///
    /// - Parameters:
    ///   - transaction: A confidential transaction.
    ///   - account: The account.
    ///   - owner: The account's owner hash.
    /// - Returns: Each output that the account received, with its UTXO.
    /// - Throws: A cipher or key agreement error.
    private static func confidentialUTXOs(
        in transaction: ShieldedTransaction,
        of account: ShieldedAccount,
        owner: Poseidon.Element
    ) throws -> [(ShieldedOutput, UTXO)] {
        // A transaction without a valid viewing key or salt carries no note that the account can open.
        guard let viewingKeyBytes = transaction.transactionViewingKey, let salt = transaction.salt,
              let transactionViewingPublicKey = try? P256.KeyAgreement.PublicKey(compressedRepresentation: viewingKeyBytes) else {
            return []
        }
        let viewTags = account.viewTags
        return try transaction.outputs.enumerated().compactMap { index, output in
            guard viewTags.contains(output.viewTag),
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
