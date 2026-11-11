import CryptoKit
import ModularArithmetic
public import RPC
public import Transactions

/// A default-ring owner that can receive SOL: the public half of a shielded address.
public struct Recipient: Sendable {
    /// Keys that can't own a default-ring UTXO.
    public enum ValidationError: Error, Equatable {
        case offCurveSigningAddress
    }

    public let signingAddress: Address

    let nullifierPublicKey: Poseidon.Element

    let viewingPublicKey: Curve25519.KeyAgreement.PublicKey

    /// The owner hash that the owner's UTXOs commit to.
    let owner: Poseidon.Element

    var viewTag: [UInt8] { signingAddress.bytes }

    /// Creates a recipient from a shielded address's keys.
    ///
    /// - Parameters:
    ///   - signingAddress: The owner's Ed25519 signing address.
    ///   - nullifierPublicKey: The public key of the owner's nullifier key.
    ///   - viewingPublicKey: The owner's viewing public key.
    /// - Throws: ``ValidationError/offCurveSigningAddress`` if the signing address isn't an Ed25519
    ///   point.
    init(signingAddress: Address, nullifierPublicKey: Poseidon.Element, viewingPublicKey: Curve25519.KeyAgreement.PublicKey) throws {
        guard signingAddress.isOnCurve else { throw ValidationError.offCurveSigningAddress }
        self.signingAddress = signingAddress
        self.nullifierPublicKey = nullifierPublicKey
        self.viewingPublicKey = viewingPublicKey
        owner = OwnerIdentity.ownerHash(signingPublicKey: signingAddress.bytes, nullifierPublicKey: nullifierPublicKey)
    }

    /// Looks up owners' shielded addresses in the user registry.
    ///
    /// - Parameters:
    ///   - owners: One to 100 owners' signing addresses.
    ///   - rpc: The client of the network whose registry to read.
    /// - Returns: Each owner as a recipient, or `nil` if the owner hasn't registered, in the owners'
    ///   order.
    /// - Throws: An error from ``RPC/RPC/accounts(at:minContextSlot:)``, or a ``UserRegistry/ValidationError`` if an
    ///   account at a record's address isn't a valid record of its owner.
    @concurrent
    public static func lookup(_ owners: [Address], using rpc: some RPC) async throws -> [Recipient?] {
        try await UserRegistry.recipients(of: owners, using: rpc)
    }
}
