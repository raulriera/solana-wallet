import CryptoKit
import Encoding
import Foundation
import ModularArithmetic
public import Transactions

extension ShieldedPool {
    private static let depositTag: UInt8 = 15

    private static let solAssetKind: UInt8 = 0

    private static let splAssetKind: UInt8 = 1

    private static let depositBlindingDomain = Array("Deposit".utf8)

    /// Creates a proofless deposit of a public asset into one recipient's default-ring UTXO: SOL from the depositor's
    /// account, or a token from the depositor's associated token account.
    ///
    /// - Parameters:
    ///   - amount: The positive amount to deposit, in the asset's smallest unit, excluding fees.
    ///   - asset: The asset to deposit.
    ///   - depositor: The wallet that pays the amount and signs.
    ///   - recipient: The owner of the new UTXO.
    ///   - treeID: The ID of the tree that receives the UTXO.
    /// - Returns: The deposit instruction.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` for a zero amount, or another
    ///   ``Transactions/ValidationError`` if an account's derivation fails.
    public static func deposit(
        _ amount: UInt64, of asset: PrivateAsset, from depositor: Address, to recipient: Recipient, treeID: UInt16
    ) throws -> Instruction {
        switch asset {
        case .nativeSOL:
            return try deposit(amount, kind: [solAssetKind], from: depositor, to: recipient, treeID: treeID, settlement: [
                .readonly(try SystemProgram.address),
                .writable(try solInterface),
            ])
        case .token(let token):
            let mint = token.mint
            let interface = try splInterface(of: mint)
            return try deposit(amount, kind: [splAssetKind, interface.bump], from: depositor, to: recipient, treeID: treeID, settlement: [
                .readonly(try PrivateToken.program.address),
                .readonly(mint),
                .writable(try PrivateToken.program.associatedAccount(owner: depositor, mint: mint)),
                .writable(interface.address),
            ])
        }
    }

    /// Creates a proofless deposit of one asset into one recipient's default-ring UTXO.
    ///
    /// - Parameters:
    ///   - amount: The positive amount to deposit.
    ///   - kind: The encoded asset kind of the deposit's settlement.
    ///   - depositor: The wallet that pays the amount and signs.
    ///   - recipient: The owner of the new UTXO.
    ///   - treeID: The ID of the tree that receives the UTXO.
    ///   - settlement: The accounts that the asset kind names, in order.
    /// - Returns: The deposit instruction.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` for a zero amount, or another
    ///   ``Transactions/ValidationError`` if an account's derivation fails.
    private static func deposit(
        _ amount: UInt64,
        kind: [UInt8],
        from depositor: Address,
        to recipient: Recipient,
        treeID: UInt16,
        settlement: [Transaction.Account]
    ) throws -> Instruction {
        guard amount > 0 else { throw ValidationError.invalidAmount }
        var writer = WincodeWriter()
        writer.append(depositTag)
        try writer.appendCount(1)
        writer.append(array: kind)
        try writer.appendCount(1)
        writer.append(UInt8(0))
        writer.append(array: recipient.viewTag)
        writer.append(array: recipient.owner.bigEndianBytes)
        writer.append(amount)
        writer.appendNone()
        return Instruction(program: try address, accounts: [
            .writable(try tree(id: treeID)),
            .writable(depositor, isSigner: true),
            .readonly(try address),
        ] + settlement, data: Data(writer.bytes))
    }

    /// Derives the blinding that the program gives a deposited UTXO.
    ///
    /// - Parameters:
    ///   - tree: The account of the tree that holds the UTXO.
    ///   - leafIndex: The UTXO's position in the tree.
    /// - Returns: The blinding.
    static func depositBlinding(tree: Address, leafIndex: UInt64) -> Poseidon.Element {
        var preimage = depositBlindingDomain + tree.bytes
        preimage.append(bigEndian: leafIndex)
        var digest = Array(SHA256.hash(data: preimage))
        digest[0] = 0
        return Poseidon.Element(reducing: digest)
    }
}
