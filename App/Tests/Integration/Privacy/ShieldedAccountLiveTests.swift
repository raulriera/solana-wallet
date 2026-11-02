import CryptoKit
import Encoding
import Privacy
import RPC
import Testing
import Transactions

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct ShieldedAccountLiveTests {
    @Test(arguments: ShieldedPoolOwners.devnet)
    func `Registered owners read as registered with other keys`(owner: String) async throws {
        let account = try Self.randomKeys(for: Address(owner))

        let registration = try await account.registration(using: Solana(network: .devnet))

        #expect(registration == .registeredWithOtherKeys)
    }

    @Test
    func `Random addresses are unregistered`() async throws {
        let address = try Address(Base58.encode(Array(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)))

        let registration = try await Self.randomKeys(for: address).registration(using: Solana(network: .devnet))

        #expect(registration == .unregistered)
    }

    @Test
    func `Syncs with other keys find no notes and resume`() async throws {
        let account = try Self.randomKeys(for: Address(ShieldedPoolOwners.devnet[0]))
        let (rpc, indexer) = (Solana(network: .devnet), Zolana(network: .devnet))

        let first = try await NoteSyncState().synced(for: account, rpc: rpc, indexer: indexer)
        let later = try await first.synced(for: account, rpc: rpc, indexer: indexer)

        #expect(first.notes.isEmpty)
        #expect(first != NoteSyncState())
        #expect(later.notes.isEmpty)
        #expect(later.lamports == 0)
    }

    private static func randomKeys(for address: Address) throws -> ShieldedAccount {
        try ShieldedAccount(
            signingAddress: address, nullifierSecret: SymmetricKey(size: SymmetricKeySize(bitCount: 248)),
            viewingKey: Curve25519.KeyAgreement.PrivateKey()
        )
    }
}
