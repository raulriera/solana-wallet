import CryptoKit
import Foundation
import Privacy
import Transactions
import Wallet

/// One account's private-balance keys as this device keeps them: the nullifier secret and the viewing key's raw scalar.
///
/// Decoding rejects a nullifier secret that isn't 31 bytes and a viewing key that isn't a P-256 scalar. Descriptions
/// and reflection omit both keys.
nonisolated struct PrivateBalanceKeyRecord: Codable, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    /// The encoded fields of a record.
    private enum CodingKeys: String, CodingKey {
        case nullifierSecret, viewingKey
    }

    /// The length of a nullifier secret.
    private static let nullifierSecretLength = 31

    /// The 31-byte nullifier secret.
    private let nullifierSecret: Data
    /// The viewing key's 32-byte raw scalar.
    private let viewingKey: Data

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
    }

    /// Decodes a record and checks that both keys are usable.
    /// - Parameter decoder: The decoder that supplies the record's fields.
    /// - Throws: A decoding error for a missing field, a nullifier secret that isn't 31 bytes, or a viewing key that
    ///   isn't a P-256 scalar.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nullifierSecret = try container.decode(Data.self, forKey: .nullifierSecret)
        viewingKey = try container.decode(Data.self, forKey: .viewingKey)
        guard nullifierSecret.count == Self.nullifierSecretLength else {
            throw DecodingError.dataCorruptedError(forKey: .nullifierSecret, in: container,
                                                   debugDescription: "A nullifier secret has 31 bytes.")
        }
        guard (try? P256.KeyAgreement.PrivateKey(rawRepresentation: viewingKey)) != nil else {
            throw DecodingError.dataCorruptedError(forKey: .viewingKey, in: container,
                                                   debugDescription: "A viewing key is a P-256 scalar.")
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
}
