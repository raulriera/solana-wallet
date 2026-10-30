import CryptoKit
import Foundation
import Privacy
import Transactions
import Wallet

/// An account's stored private-balance keys: the nullifier secret, the viewing key's raw scalar, and the code root.
nonisolated struct PrivateBalanceKeyRecord: Codable, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    /// The encoded fields of a record.
    private enum CodingKeys: String, CodingKey {
        case nullifierSecret, viewingKey, codeRoot
    }

    /// The length of a nullifier secret, in bytes.
    private static let nullifierSecretLength = 31

    /// The length of a code root, in bytes.
    private static let codeRootLength = 32

    private let nullifierSecret: Data
    /// The viewing key's raw scalar.
    private let viewingKey: Data
    /// The root that derives the account's one-time accounts.
    private let codeRoot: Data

    var description: String { "PrivateBalanceKeyRecord" }

    var debugDescription: String { description }

    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates a record of an account's keys.
    ///
    /// - Parameter keys: The account's private-balance keys.
    init(_ keys: PrivateBalanceKeys) {
        nullifierSecret = keys.nullifierSecret.withUnsafeBytes { Data($0) }
        viewingKey = keys.viewingKey.rawRepresentation
        codeRoot = keys.codeRoot.withUnsafeBytes { Data($0) }
    }

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

    /// Returns the account's shielded keys.
    ///
    /// - Parameter address: The account's address.
    /// - Returns: The account's shielded keys.
    /// - Throws: A CryptoKit or validation error for invalid keys.
    func shieldedAccount(for address: Address) throws -> ShieldedAccount {
        try ShieldedAccount(signingAddress: address, nullifierSecret: SymmetricKey(data: nullifierSecret),
                            viewingKey: P256.KeyAgreement.PrivateKey(rawRepresentation: viewingKey))
    }

    /// Derives the one-time account at an index of the code root.
    ///
    /// - Parameter index: The one-time account's index, below 2³¹.
    /// - Returns: The one-time account.
    /// - Throws: ``Wallet/OneTimeAccountError/invalidIndex`` for an index of 2³¹ or more, or a derivation error.
    func oneTimeAccount(at index: UInt32) throws -> OneTimeAccount {
        try OneTimeAccount(codeRoot: SymmetricKey(data: codeRoot), index: index)
    }

    /// Derives the address of the one-time account at an index of the code root.
    ///
    /// - Parameter index: The one-time account's index, below 2³¹.
    /// - Returns: The one-time account's address.
    /// - Throws: ``Wallet/OneTimeAccountError/invalidIndex`` for an index of 2³¹ or more, or a derivation error.
    func oneTimeAddress(at index: UInt32) throws -> Address {
        try Address(OneTimeAccount.address(codeRoot: SymmetricKey(data: codeRoot), index: index))
    }
}
