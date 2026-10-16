import CryptoKit
import Foundation
import ModularArithmetic
import Transactions

extension ShieldedPool {
    /// The tag of the proofless `deposit` instruction.
    private static let depositTag: UInt8 = 15

    /// The kind of a native-SOL settlement group, `DepositAssetKind::Sol`.
    private static let solAssetKind: UInt8 = 0

    /// The domain of a deposit's blinding, ASCII `Deposit`.
    private static let depositBlindingDomain = Array("Deposit".utf8)

    /// Creates a proofless deposit of public SOL into one recipient's default-ring UTXO.
    ///
    /// The instruction data is the tag 15, one SOL settlement group, and one entry: the group's
    /// index 0, the recipient's view tag and owner hash, the amount as a little-endian 64-bit
    /// integer, and no memo. The program derives the UTXO's blinding from the tree and the leaf
    /// index, so the depositor commits to nothing else. The accounts are the tree, the depositor as
    /// a writable signer, the shielded-pool program, the System Program, and the writable SOL
    /// interface.
    ///
    /// - Parameters:
    ///   - lamports: The positive amount to deposit, excluding fees.
    ///   - depositor: The wallet that pays the lamports and signs.
    ///   - recipient: The owner of the new UTXO, which may be the depositor's own shielded address.
    ///   - treeID: The ID of the tree that receives the UTXO.
    /// - Returns: The instruction, which can be composed with other program invocations.
    /// - Throws: ``ValidationError/invalidAmount`` for zero lamports, or another
    ///   ``ValidationError`` if an account's derivation fails, which doesn't happen.
    static func deposit(lamports: UInt64, from depositor: Address, to recipient: Recipient, treeID: UInt16) throws -> Instruction {
        guard lamports > 0 else { throw ValidationError.invalidAmount }
        var writer = WincodeWriter()
        writer.append(depositTag)
        try writer.appendCount(1)
        writer.append(solAssetKind)
        try writer.appendCount(1)
        // The entry's index into the settlement groups.
        writer.append(UInt8(0))
        writer.append(array: recipient.viewTag)
        writer.append(array: recipient.owner.bigEndianBytes)
        writer.append(lamports)
        writer.appendNone()
        return Instruction(program: try program, accounts: [
            .init(address: try tree(id: treeID), isSigner: false, isWritable: true),
            .init(address: depositor, isSigner: true, isWritable: true),
            .init(address: try program, isSigner: false, isWritable: false),
            .init(address: try systemProgram, isSigner: false, isWritable: false),
            .init(address: try solInterface, isSigner: false, isWritable: true),
        ], data: Data(writer.bytes))
    }

    /// Derives the blinding that the program gives a deposited UTXO, `deposit_blinding`.
    ///
    /// The blinding is SHA-256 of `Deposit`, the tree's address, and the UTXO's leaf index as a
    /// big-endian 64-bit integer, with its first byte set to zero so it's a field element. A tree
    /// position holds one UTXO, so no two deposits share a blinding. The deposit's payload also
    /// publishes the blinding; a recipient recomputes it to check the payload.
    ///
    /// - Parameters:
    ///   - tree: The account of the tree that holds the UTXO.
    ///   - leafIndex: The UTXO's position in the tree.
    /// - Returns: The blinding.
    static func depositBlinding(tree: Address, leafIndex: UInt64) -> Poseidon.Element {
        let preimage = depositBlindingDomain + tree.bytes + Swift.withUnsafeBytes(of: leafIndex.bigEndian, Array.init)
        var digest = Array(SHA256.hash(data: preimage))
        digest[0] = 0
        return Poseidon.Element(reducing: digest)
    }
}
