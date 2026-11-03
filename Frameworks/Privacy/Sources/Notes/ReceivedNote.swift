import CryptoKit
import Foundation
import ModularArithmetic
import RPC
import Transactions

/// A SOL UTXO that an account received, with its position, its transaction, and its nullifier.
public struct ReceivedNote: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The keys of a note's encoded fields.
    private enum CodingKeys: String, CodingKey {
        case owner, mint, amount, blinding, treeID, leafIndex, signature, slot, nullifier
    }

    let utxo: UTXO

    let leafIndex: UInt64

    /// The signature of the transaction that created the UTXO.
    public let signature: String

    /// The slot of the transaction that created the UTXO.
    public let slot: UInt64

    let nullifier: Poseidon.Element

    public var lamports: UInt64 { utxo.amount }

    public var treeID: UInt16 { utxo.treeID }

    public var description: String { "ReceivedNote" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates a note.
    ///
    /// - Parameters:
    ///   - utxo: The received UTXO.
    ///   - leafIndex: The UTXO's position in its tree.
    ///   - signature: The signature of the transaction that created the UTXO.
    ///   - slot: The slot of the transaction that created the UTXO.
    ///   - nullifier: The nullifier that a spend of the UTXO publishes.
    init(utxo: UTXO, leafIndex: UInt64, signature: String, slot: UInt64, nullifier: Poseidon.Element) {
        self.utxo = utxo
        self.leafIndex = leafIndex
        self.signature = signature
        self.slot = slot
        self.nullifier = nullifier
    }

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
    /// - Throws: A decoding error if the field is missing or isn't a canonical field element.
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
    ///   - transaction: The shielded transaction.
    ///   - account: The account that receives the notes.
    /// - Returns: The account's notes, in output order.
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
    ///   - account: The account that receives the outputs.
    ///   - owner: The account's owner hash.
    /// - Returns: Each output that the account received, with its UTXO.
    /// - Throws: ``SlotCipher/CipherError/cryptorFailed`` if CommonCrypto fails.
    private static func confidentialUTXOs(
        in transaction: ShieldedTransaction,
        of account: ShieldedAccount,
        owner: Poseidon.Element
    ) throws -> [(ShieldedOutput, UTXO)] {
        guard let viewingKeyBytes = transaction.transactionViewingKey, let salt = transaction.salt,
              let transactionViewingPublicKey = try? Curve25519.KeyAgreement.PublicKey(taggedRepresentation: viewingKeyBytes) else {
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
    /// - Throws: A ``Transactions/ValidationError`` if a tree account's derivation fails.
    private static func deposits(in transaction: ShieldedTransaction, owner: Poseidon.Element) throws -> [(ShieldedOutput, UTXO)] {
        try transaction.outputs.compactMap { output in try depositUTXO(in: output, owner: owner).map { (output, $0) } }
    }

    /// Rebuilds a proofless deposit's UTXO if it belongs to an owner hash.
    ///
    /// - Parameters:
    ///   - output: A proofless deposit's output.
    ///   - owner: The owner hash.
    /// - Returns: The UTXO, or `nil` if the output isn't a valid SOL deposit for `owner`.
    /// - Throws: A ``Transactions/ValidationError`` if the tree account's derivation fails.
    static func depositUTXO(in output: ShieldedOutput, owner: Poseidon.Element) throws -> UTXO? {
        guard let deposit = try? ProoflessOutput(decoding: output.payload),
              deposit.owner == owner, deposit.mint == ConfidentialPlaintext.Asset.sol.mint,
              deposit.blinding == ShieldedPool.depositBlinding(tree: try ShieldedPool.tree(id: output.treeID), leafIndex: output.leafIndex),
              let utxoHash = Poseidon.Element(bigEndianBytes: output.utxoHash) else { return nil }
        let utxo = UTXO(owner: owner, mint: deposit.mint, amount: deposit.amount, blinding: deposit.blinding, treeID: output.treeID)
        return utxo.hash == utxoHash ? utxo : nil
    }
}
