import CryptoKit
import Encoding
import Privacy
import RPC
import Testing
import Transactions

/// Verifies the registration and note sync of shielded accounts with random keys against real devnet
/// owners, with read-only requests.
///
/// The owners are ``ShieldedPoolOwners``: each holds a user-registry record and paid for a proofless
/// deposit to its own view tag, under keys that these tests don't have. Registry records come from the public devnet RPC; notes come from Helius's indexer.
@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct ShieldedAccountLiveTests {
    /// Verifies that an owner's record doesn't register random keys for the owner's address.
    ///
    /// - Parameter owner: The owner's base-58 address.
    /// - Throws: A provider, validation, or test prerequisite error.
    @Test(arguments: ShieldedPoolOwners.devnet)
    func `Registered owners read as registered with other keys`(owner: String) async throws {
        let account = try Self.randomKeys(for: Address(owner))

        let registration = try await account.registration(using: Solana(network: .devnet))

        #expect(registration == .registeredWithOtherKeys)
    }

    /// Verifies that a random Ed25519 address is unregistered.
    ///
    /// - Throws: A provider, validation, or test prerequisite error.
    @Test
    func `Random addresses are unregistered`() async throws {
        let address = try Address(Base58.encode(Array(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)))

        let registration = try await Self.randomKeys(for: address).registration(using: Solana(network: .devnet))

        #expect(registration == .unregistered)
    }

    /// Syncs an owner's address with random keys, which open none of its notes, then syncs again from
    /// the stored position.
    ///
    /// - Throws: A credential, provider, decoding, or test prerequisite error.
    @Test
    func `Syncs with other keys find no notes and resume`() async throws {
        let account = try Self.randomKeys(for: Address(ShieldedPoolOwners.devnet[0]))
        let provider = HeliusRPC(apiKey: try LiveClients.heliusAPIKey(), network: .devnet)

        let first = try await NoteSyncState().synced(for: account, using: provider)
        let later = try await first.synced(for: account, using: provider)

        #expect(first.notes.isEmpty)
        #expect(first != NoteSyncState())
        #expect(later.notes.isEmpty)
        #expect(later.lamports == 0)
    }

    /// Creates an account with random private-balance keys.
    ///
    /// - Parameter address: The account's signing address.
    /// - Returns: The account.
    /// - Throws: An error if the nullifier secret doesn't have 31 bytes, which doesn't happen.
    private static func randomKeys(for address: Address) throws -> ShieldedAccount {
        try ShieldedAccount(
            signingAddress: address, nullifierSecret: SymmetricKey(size: SymmetricKeySize(bitCount: 248)),
            viewingKey: P256.KeyAgreement.PrivateKey()
        )
    }
}
