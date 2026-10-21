import CryptoKit
import Foundation
import Privacy
import Transactions
import Wallet

/// One account's private-balance keys as this device keeps them: the nullifier secret, the viewing key's raw scalar,
/// and the code root that derives the account's redeem codes.
///
/// Decoding rejects a nullifier secret that isn't 31 bytes, a viewing key that isn't a P-256 scalar, and a code root
/// that isn't 32 bytes. Descriptions and reflection omit the keys.
nonisolated struct PrivateBalanceKeyRecord: Codable, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    /// The encoded fields of a record.
    private enum CodingKeys: String, CodingKey {
        case nullifierSecret, viewingKey, codeRoot
    }

    /// The length of a nullifier secret.
    private static let nullifierSecretLength = 31

    /// The length of a code root.
    private static let codeRootLength = 32

    /// The 31-byte nullifier secret.
    private let nullifierSecret: Data
    /// The viewing key's 32-byte raw scalar.
    private let viewingKey: Data
    /// The 32-byte root of the account's one-time accounts.
    private let codeRoot: Data

    /// A description that omits the keys.
    var description: String { "PrivateBalanceKeyRecord" }

    /// A debugging description that omits the keys.
    var debugDescription: String { description }

    /// A reflection view that omits the keys.
    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Keeps the keys that Wallet derived for an account.
    /// - Parameter keys: The account's private-balance keys.
    init(_ keys: PrivateBalanceKeys) {
        nullifierSecret = keys.nullifierSecret.withUnsafeBytes { Data($0) }
        viewingKey = keys.viewingKey.rawRepresentation
        codeRoot = keys.codeRoot.withUnsafeBytes { Data($0) }
    }

    /// Decodes a record and checks that its keys are usable.
    /// - Parameter decoder: The decoder that supplies the record's fields.
    /// - Throws: A decoding error for a missing field, a nullifier secret that isn't 31 bytes, a viewing key that isn't
    ///   a P-256 scalar, or a code root that isn't 32 bytes.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nullifierSecret = try container.decode(Data.self, forKey: .nullifierSecret)
        viewingKey = try container.decode(Data.self, forKey: .viewingKey)
        codeRoot = try container.decode(Data.self, forKey: .codeRoot)
        guard nullifierSecret.count == Self.nullifierSecretLength else {
            throw DecodingError.dataCorruptedError(forKey: .nullifierSecret, in: container,
                                                   debugDescription: "A nullifier secret has 31 bytes.")
        }
        guard (try? P256.KeyAgreement.PrivateKey(rawRepresentation: viewingKey)) != nil else {
            throw DecodingError.dataCorruptedError(forKey: .viewingKey, in: container,
                                                   debugDescription: "A viewing key is a P-256 scalar.")
        }
        guard codeRoot.count == Self.codeRootLength else {
            throw DecodingError.dataCorruptedError(forKey: .codeRoot, in: container,
                                                   debugDescription: "A code root has 32 bytes.")
        }
    }

    /// Pairs the keys with the account's address for Privacy's registration and note sync.
    /// - Parameter address: The account's address, which derived these keys.
    /// - Returns: The account's shielded keys.
    /// - Throws: A CryptoKit error for a viewing key that isn't a P-256 scalar, or Privacy's validation error for a
    ///   nullifier secret that isn't 31 bytes; decoding rejects both.
    func shieldedAccount(for address: Address) throws -> ShieldedAccount {
        try ShieldedAccount(signingAddress: address, nullifierSecret: SymmetricKey(data: nullifierSecret),
                            viewingKey: P256.KeyAgreement.PrivateKey(rawRepresentation: viewingKey))
    }

    /// Derives the one-time account at an index of the account's code root, such as a redeem code's.
    /// - Parameter index: The one-time account's index, below 2³¹.
    /// - Returns: The one-time account.
    /// - Throws: ``Wallet/OneTimeAccountError/invalidIndex`` for an index of 2³¹ or more, or a derivation error.
    func oneTimeAccount(at index: UInt32) throws -> OneTimeAccount {
        try OneTimeAccount(codeRoot: SymmetricKey(data: codeRoot), index: index)
    }

    /// Derives only the address of the one-time account at an index of the account's code root, without its
    /// private-balance keys, such as to read many indices' view tags.
    /// - Parameter index: The one-time account's index, below 2³¹.
    /// - Returns: The one-time account's address.
    /// - Throws: ``Wallet/OneTimeAccountError/invalidIndex`` for an index of 2³¹ or more, or a derivation error.
    func oneTimeAddress(at index: UInt32) throws -> Address {
        try Address(OneTimeAccount.address(codeRoot: SymmetricKey(data: codeRoot), index: index))
    }
}
