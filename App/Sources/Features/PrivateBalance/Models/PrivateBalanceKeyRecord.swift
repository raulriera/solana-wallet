import CryptoKit
import Foundation
import Privacy
import Redaction
import Transactions
import Wallet

/// An account's stored private-balance keys: the nullifier secret, the viewing key's raw scalar, and the code root.
nonisolated struct PrivateBalanceKeyRecord: Codable, Equatable, Sendable, Redacted {
    /// The encoded fields of a record.
    private enum CodingKeys: String, CodingKey {
        case nullifierSecret, viewingSecret, codeRoot
    }

    /// The length of a nullifier secret, in bytes.
    private static let nullifierSecretLength = 31

    /// The length of a viewing secret, in bytes.
    private static let viewingSecretLength = 32

    /// The length of a code root, in bytes.
    private static let codeRootLength = 32

    private let nullifierSecret: Data
    private let viewingSecret: Data
    /// The root that derives the account's one-time accounts.
    private let codeRoot: Data

    /// Creates a record of an account's keys.
    ///
    /// - Parameter keys: The account's private-balance keys.
    init(_ keys: PrivateBalanceKeys) {
        nullifierSecret = keys.nullifierSecret.withUnsafeBytes { Data($0) }
        viewingSecret = keys.viewingKey.rawRepresentation
        codeRoot = keys.codeRoot.withUnsafeBytes { Data($0) }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nullifierSecret = try container.decode(Data.self, forKey: .nullifierSecret)
        viewingSecret = try container.decode(Data.self, forKey: .viewingSecret)
        codeRoot = try container.decode(Data.self, forKey: .codeRoot)
        guard nullifierSecret.count == Self.nullifierSecretLength else {
            throw DecodingError.dataCorruptedError(forKey: .nullifierSecret, in: container,
                                                   debugDescription: "A nullifier secret has 31 bytes.")
        }
        guard viewingSecret.count == Self.viewingSecretLength else {
            throw DecodingError.dataCorruptedError(forKey: .viewingSecret, in: container,
                                                   debugDescription: "A viewing secret has 32 bytes.")
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
                            viewingKey: Curve25519.KeyAgreement.PrivateKey(rawRepresentation: viewingSecret))
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
