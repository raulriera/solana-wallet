import CryptoKit
import Foundation
import ModularArithmetic
import RPC
import Transactions

/// The user registry, whose program-derived records publish owners' shielded addresses.
public enum UserRegistry {
    /// A registry read that didn't return a valid record of the requested owner.
    public enum ValidationError: Error, Equatable {
        case invalidLength
        case invalidDiscriminator
        case ownerMismatch
        case nonCanonicalBump
        /// The record's nullifier public key isn't a canonical field element.
        case invalidNullifierPublicKey
        /// The record's viewing public key isn't a tagged X25519 public key.
        case invalidViewingPublicKey
        /// The record's merging flag isn't 0 or 1.
        case invalidMergingFlag
    }

    private static let programID = "regy3WAeRXMYuMYxr5iK3Bf9Arr3PcxGxyzAddbiqDQ"

    private static let recordSeed = Array("zolana/registry/v0".utf8)

    /// The length of a record's account, in bytes.
    static let recordLength = 100

    private static let discriminator: UInt8 = 1

    private static let ownerRange = 1..<33

    private static let bumpIndex = 33

    private static let nullifierPublicKeyRange = 34..<66

    private static let viewingPublicKeyRange = 66..<99

    private static let mergingFlagIndex = 99

    static var program: Address {
        get throws { try Address(programID) }
    }

    /// Derives an owner's record and its canonical bump.
    ///
    /// - Parameter owner: The owner's signing address.
    /// - Returns: The record's address and bump.
    /// - Throws: A ``Transactions/ValidationError`` if the derivation fails.
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
        guard let nullifierPublicKey = Poseidon.Element(bigEndianBytes: Array(data[nullifierPublicKeyRange])) else {
            throw ValidationError.invalidNullifierPublicKey
        }
        let viewingPublicKey: Curve25519.KeyAgreement.PublicKey
        do {
            viewingPublicKey = try Curve25519.KeyAgreement.PublicKey(taggedRepresentation: data[viewingPublicKeyRange])
        } catch {
            throw ValidationError.invalidViewingPublicKey
        }
        guard data[mergingFlagIndex] <= 1 else { throw ValidationError.invalidMergingFlag }
        return try Recipient(signingAddress: owner, nullifierPublicKey: nullifierPublicKey, viewingPublicKey: viewingPublicKey)
    }

    /// Looks up owners' shielded addresses.
    ///
    /// - Parameters:
    ///   - owners: One to 100 owners' signing addresses.
    ///   - rpc: The client that reads the records.
    /// - Returns: Each owner as a recipient, or `nil` if the owner hasn't registered, in the
    ///   owners' order.
    /// - Throws: An error from ``RPC/RPC/accounts(at:minContextSlot:)``, or a validation error from
    ///   ``recipient(of:from:)``.
    @concurrent
    static func recipients(of owners: [Address], using rpc: some RPC) async throws -> [Recipient?] {
        let accounts = try await rpc.accounts(at: owners.map { try record(of: $0).address.value }).value
        return try zip(owners, accounts).map { try recipient(of: $0, from: $1) }
    }
}
