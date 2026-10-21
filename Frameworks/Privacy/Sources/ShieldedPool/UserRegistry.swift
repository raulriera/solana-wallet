import CryptoKit
import Foundation
import ModularArithmetic
import RPC
import Transactions

/// zolana's user registry: the program-derived record that publishes an owner's shielded address.
///
/// Each record lives at the address derived from `zolana/registry/v0` and the owner's 32 bytes,
/// with the canonical bump. The program allocates 134 bytes and writes zolana's Borsh `UserRecord`:
/// the discriminator 1, the owner, the bump, an optional 33-byte P-256 owner, the nullifier
/// public key, the compressed P-256 viewing public key, and the merging flag. An Ed25519 owner has
/// no P-256 owner, so the fields shift and zeros fill the rest. A missing account, or one that the
/// registry program doesn't own, means that the owner hasn't registered; a lookup needs only
/// standard RPC.
public enum UserRegistry {
    /// A registry read that didn't return a valid record of the requested owner.
    public enum ValidationError: Error, Equatable {
        /// The account doesn't have a record's 134 bytes.
        case invalidLength
        /// The account's first byte isn't a record's discriminator.
        case invalidDiscriminator
        /// The record names another owner.
        case ownerMismatch
        /// The record's bump isn't the canonical bump of its address.
        case nonCanonicalBump
        /// The record's owner signs with P-256, which this module doesn't support.
        case unsupportedP256Owner
        /// The record's optional P-256 owner has an invalid tag.
        case invalidOptionTag
        /// The record's nullifier public key isn't a canonical field element.
        case invalidNullifierPublicKey
        /// The record's viewing public key isn't a compressed P-256 point.
        case invalidViewingPublicKey
        /// The record's merging flag isn't 0 or 1.
        case invalidMergingFlag
        /// The provider returned a different number of accounts than the lookup asked for.
        case mismatchedResponse
    }

    /// The registry program's address.
    private static let programID = "regyS5rkAcw2YzDJCmTwCTHs2s246FXxbmuRZ42u2PD"

    /// The seed prefix of a record.
    private static let recordSeed = Array("zolana/registry/v0".utf8)

    /// The length of a record's account.
    static let recordLength = 134

    /// The discriminator of a record.
    private static let discriminator: UInt8 = 1

    /// The position of the owner's address in a record.
    private static let ownerRange = 1..<33

    /// The position of the bump in a record.
    private static let bumpIndex = 33

    /// The position of the optional P-256 owner's tag in a record.
    private static let optionTagIndex = 34

    /// The position of an Ed25519 owner's nullifier public key in its record.
    private static let nullifierPublicKeyRange = 35..<67

    /// The position of an Ed25519 owner's viewing public key in its record.
    private static let viewingPublicKeyRange = 67..<100

    /// The position of an Ed25519 owner's merging flag in its record.
    private static let mergingFlagIndex = 100

    /// The registry program.
    ///
    /// - Throws: ``Transactions/ValidationError/invalidAddress`` if the program ID doesn't decode,
    ///   which doesn't happen.
    static var program: Address {
        get throws { try Address(programID) }
    }

    /// Derives an owner's record and its canonical bump.
    ///
    /// - Parameter owner: The owner's signing address.
    /// - Returns: The record's address and bump.
    /// - Throws: A ``Transactions/ValidationError`` if the derivation fails, which doesn't happen.
    static func record(of owner: Address) throws -> (address: Address, bump: UInt8) {
        try ProgramAddress.find(seeds: [recordSeed, owner.bytes], program: program)
    }

    /// Reads an owner's shielded address from the account at its record.
    ///
    /// - Parameters:
    ///   - owner: The owner's signing address.
    ///   - account: The account at ``record(of:)``, or `nil` if none exists.
    /// - Returns: The owner as a recipient, or `nil` if the owner hasn't registered.
    /// - Throws: A ``ValidationError`` if the account isn't a valid record of the owner, or a
    ///   ``Recipient/ValidationError`` if no key can sign for the owner's address.
    static func recipient(of owner: Address, from account: Account?) throws -> Recipient? {
        guard let account, account.owner == programID else { return nil }
        let data = [UInt8](account.data)
        guard data.count == recordLength else { throw ValidationError.invalidLength }
        guard data[0] == discriminator else { throw ValidationError.invalidDiscriminator }
        guard Array(data[ownerRange]) == owner.bytes else { throw ValidationError.ownerMismatch }
        guard data[bumpIndex] == (try record(of: owner)).bump else { throw ValidationError.nonCanonicalBump }
        switch data[optionTagIndex] {
        case 0: break
        case 1: throw ValidationError.unsupportedP256Owner
        default: throw ValidationError.invalidOptionTag
        }
        guard let nullifierPublicKey = Poseidon.Element(bigEndianBytes: Array(data[nullifierPublicKeyRange])) else {
            throw ValidationError.invalidNullifierPublicKey
        }
        let viewingPublicKey: P256.KeyAgreement.PublicKey
        do {
            viewingPublicKey = try P256.KeyAgreement.PublicKey(compressedRepresentation: data[viewingPublicKeyRange])
        } catch {
            throw ValidationError.invalidViewingPublicKey
        }
        guard data[mergingFlagIndex] <= 1 else { throw ValidationError.invalidMergingFlag }
        return try Recipient(signingAddress: owner, nullifierPublicKey: nullifierPublicKey, viewingPublicKey: viewingPublicKey)
    }

    /// Looks up owners' shielded addresses with one finalized `getMultipleAccounts` read.
    ///
    /// - Parameters:
    ///   - owners: One to 100 owners' signing addresses.
    ///   - rpc: The client that reads the records.
    /// - Returns: Each owner as a recipient, or `nil` if the owner hasn't registered, in the
    ///   owners' order.
    /// - Throws: ``RPC/GetMultipleAccountsError/invalidAddressCount`` for no owners or more than
    ///   100, an RPC error, ``ValidationError/mismatchedResponse`` if the provider returns another
    ///   number of accounts, or a validation error from ``recipient(of:from:)``.
    @concurrent
    static func recipients(of owners: [Address], using rpc: some RPC) async throws -> [Recipient?] {
        let records = try owners.map { try record(of: $0).address.value }
        let response = try await rpc.send(GetMultipleAccounts(addresses: records))
        guard response.value.count == owners.count else { throw ValidationError.mismatchedResponse }
        return try zip(owners, response.value).map { try recipient(of: $0, from: $1) }
    }
}
