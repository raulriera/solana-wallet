import CryptoKit
import Encoding
import Foundation
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

/// Public-fixture accounts with their private-balance keys, and the registry records and deposits that a local
/// provider returns for them.
///
/// Records and deposits are built from the account's keys as the user-registry and shielded-pool programs write them.
enum PrivateBalanceFixtures {
    /// The recovery identity of every fixture account.
    static let recoveryID = UUID(uuidString: "2C4B8E7A-3F61-4D0B-9E25-6A7D1C3B5F80")!

    /// A registry read that finds no record.
    static let unregistered = #"{"context":{"slot":7},"value":[null]}"#

    /// The published recovery that every fixture account comes from.
    /// - Returns: The public test phrase without a BIP-39 passphrase.
    /// - Throws: A validation error, which doesn't happen.
    static func recovery() throws -> Recovery {
        Recovery(phrase: try RecoveryPhrase(PublicWallet.words), passphrase: "")
    }

    /// Recovery storage that holds the published recovery.
    /// - Returns: Read-only storage with the fixture recovery under ``recoveryID``.
    /// - Throws: A validation error, which doesn't happen.
    static func recoveryStore() throws -> SecurityRecoveryStore {
        SecurityRecoveryStore(records: [recoveryID: try recovery()])
    }

    /// Derives a fixture account at `m/44'/501'/i'/0'`.
    /// - Parameter index: The account index i.
    /// - Returns: The account with its derived address.
    /// - Throws: A derivation or test prerequisite error.
    static func account(index: UInt32 = 0) async throws -> widgets.Account {
        let recovery = try recovery()
        let path = try DerivationPath("m/44'/501'/\(index)'/0'")
        let derived = try #require(try await Wallet().accounts(for: recovery.phrase, passphrase: recovery.passphrase,
                                                               paths: [path]).first)
        return widgets.Account(id: UUID(), recoveryID: recoveryID, address: try Address(derived.address), path: path)
    }

    /// Derives a fixture account's private-balance keys as Wallet does.
    /// - Parameter account: A fixture account.
    /// - Returns: The keys that enabling the account saves.
    /// - Throws: A derivation error.
    static func keys(for account: widgets.Account) async throws -> PrivateBalanceKeyRecord {
        let recovery = try recovery()
        return PrivateBalanceKeyRecord(try await Wallet().privateBalanceKeys(
            using: recovery.phrase, expectedAddress: account.address.value, passphrase: recovery.passphrase,
            path: account.path
        ))
    }

    /// Creates random keys for an address, such as the keys another app registered.
    /// - Parameter address: The account's address.
    /// - Returns: Keys that differ from the fixture account's.
    /// - Throws: A validation error, which doesn't happen.
    static func otherKeys(for address: Address) throws -> ShieldedAccount {
        try ShieldedAccount(signingAddress: address, nullifierSecret: SymmetricKey(size: SymmetricKeySize(bitCount: 248)),
                            viewingKey: P256.KeyAgreement.PrivateKey())
    }

    /// A registry read that finds the record publishing an account's keys.
    ///
    /// The record holds the discriminator 1, the owner, the canonical bump, no P-256 owner, the nullifier public key,
    /// the compressed viewing public key, and no merging, padded with zeros to 134 bytes.
    /// - Parameter account: The keys that the record publishes.
    /// - Returns: The `getMultipleAccounts` result.
    /// - Throws: A derivation error, which doesn't happen.
    static func registry(publishing account: ShieldedAccount) throws -> String {
        let owner = account.signingAddress.bytes
        var data = [1] + owner + [try UserRegistry.record(of: account.signingAddress).bump, 0]
        data += account.nullifierKey.publicKey.bigEndianBytes
        data += Array(account.viewingKey.publicKey.compressedRepresentation) + [0]
        data += [UInt8](repeating: 0, count: 134 - data.count)
        let record = #"{"owner":"\#(try UserRegistry.program.value)","lamports":1823520,"executable":false,"#
            + #""data":["\#(Data(data).base64EncodedString())","base64"]}"#
        return #"{"context":{"slot":7},"value":[\#(record)]}"#
    }

    /// A proofless deposit of SOL to an account, as an encrypted-output row of a tag read.
    ///
    /// The payload is the plaintext encoding: the tag 0, the little-endian length of the rest, the proofless scheme 0,
    /// the owner hash, the program's blinding for the output's position, SOL's zero mint, the amount, five absent
    /// options, and no memo.
    /// - Parameters:
    ///   - lamports: The deposited amount.
    ///   - account: The receiving account.
    ///   - leafIndex: The output's position in tree 1.
    /// - Returns: The row's JSON object.
    /// - Throws: A validation error, which doesn't happen.
    static func deposit(_ lamports: UInt64, to account: ShieldedAccount, leafIndex: UInt64) throws -> String {
        let treeID: UInt16 = 1
        let owner = try account.recipient.owner
        let blinding = ShieldedPool.depositBlinding(tree: try ShieldedPool.tree(id: treeID), leafIndex: leafIndex)
        let mint = [UInt8](repeating: 0, count: 32)
        let hash = UTXO(owner: owner, mint: mint, amount: lamports, blinding: blinding, treeID: treeID).hash
        let body = [0] + owner.bigEndianBytes + blinding.bigEndianBytes + mint + littleEndian(lamports)
            + [UInt8](repeating: 0, count: 5) + [0]
        let payload = [0] + littleEndian(UInt32(body.count)) + body
        let output = #"{"viewTag":"\#(account.signingAddress.value)","outputContext":{"hash":"\#(Base58.encode(hash.bigEndianBytes))","#
            + #""treeId":\#(treeID),"leafIndex":\#(leafIndex)},"payload":"\#(Data(payload).base64EncodedString())"}"#
        let signature = Base58.encode([UInt8](repeating: UInt8(truncatingIfNeeded: leafIndex + 1), count: 64))
        return #"{"slot":3,"txSignature":"\#(signature)","outputSlot":\#(output),"txViewingPk":null,"salt":null}"#
    }

    /// Encodes an integer's little-endian bytes.
    /// - Parameter value: The integer.
    /// - Returns: The bytes, least significant first.
    private static func littleEndian<Value: FixedWidthInteger>(_ value: Value) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
}
