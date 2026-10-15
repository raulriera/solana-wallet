import CryptoKit
import Encoding
import Foundation
import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

/// Verifies numbered accounts sign with their own keys from one shared recovery.
struct SharedRecoveryTests {
    /// Checks two independently known public keys while both accounts read the same recovery ID.
    @Test
    func `Two numbered accounts sign using one recovery record`() async throws {
        let fixture = try SigningFixture()
        let recoveryID = UUID()
        let accounts = try [
            Account(id: UUID(), recoveryID: recoveryID,
                address: Address("7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe"), path: .solana),
            Account(id: UUID(), recoveryID: recoveryID, address: fixture.account.address, path: DerivationPath("m/44'/501'/1'/0'")),
        ]
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let signer = Signer(rpc: (try HTTPResponses.signing()).client, store: store)

        for account in accounts {
            let preparation = try preparation(for: account.address, fixture: fixture)
            let signed = try await signer.sign(preparation, for: account, reason: "Approve account")
            let key = try Curve25519.Signing.PublicKey(rawRepresentation:
                Data(#require(Base58.decode(account.address.value, byteCount: 32))))
            #expect(key.isValidSignature(signed.transaction.signatures[0], for: preparation.message))
        }

        #expect(await store.reads.map(\.recoveryID) == [recoveryID, recoveryID])
    }

    /// Rejects an unrelated address before access and a wrong path when recovering the signing key.
    /// - Parameter field: The account field that disagrees with the reviewed signer.
    @Test(arguments: ["address", "path"])
    func `A mismatched account address or path cannot sign`(_ field: String) async throws {
        let fixture = try SigningFixture()
        let account = Account(id: fixture.account.id, recoveryID: fixture.account.recoveryID,
            address: field == "address" ? fixture.transfer.accounts[1].address : fixture.account.address,
            path: field == "path" ? .solana : fixture.account.path)
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let http = try HTTPResponses.signing()
        let signer = Signer(rpc: http.client, store: store)

        await #expect(throws: SigningError.signerMismatch) {
            try await signer.sign(fixture.preparation, for: account, reason: "Approve account")
        }

        #expect(await store.reads.count == (field == "address" ? 0 : 1))
        if field == "address" { #expect(await http.requests.isEmpty) }
    }

    /// The shorter discovery family signs with its exact stored path, not the default family.
    @Test
    func `A discovered account signs with its exact path`() async throws {
        let fixture = try SigningFixture()
        let account = try Account(id: UUID(), recoveryID: UUID(),
            address: Address("GjJyeC1r2RgkuoCWMyPYkCWSGSGLcz266EaAkLA27AhL"),
            path: DerivationPath("m/44'/501'/0'"))
        let recovery = Recovery(phrase: fixture.recovery.phrase, passphrase: "")
        let store = SigningRecoveryStore(recovery: recovery)
        let signer = Signer(rpc: (try HTTPResponses.signing()).client, store: store)
        let preparation = try preparation(for: account.address, fixture: fixture)
        let signed = try await signer.sign(preparation, for: account, reason: "Approve account")
        let key = try Curve25519.Signing.PublicKey(rawRepresentation:
            Data(#require(Base58.decode(account.address.value, byteCount: 32))))
        #expect(key.isValidSignature(signed.transaction.signatures[0], for: preparation.message))
        #expect(await store.reads.map(\.recoveryID) == [account.recoveryID])
    }

    /// Builds review bytes for the selected public account.
    /// - Parameters:
    ///   - address: The account required to sign the transfer.
    ///   - fixture: Shared fee, blockhash, and simulation observations.
    /// - Returns: The account-bound preparation.
    /// - Throws: An instruction, compilation, or decoding error.
    private func preparation(for address: Address, fixture: SigningFixture) throws -> Preparation {
        let instruction = try SystemProgram.transfer(from: address, to: fixture.transfer.accounts[1].address, lamports: 1)
        let message = try MessageBuilder().message(instructions: [instruction], payer: address,
            recentBlockhash: fixture.blockhash.value.blockhash, configuration: fixture.configuration)
        let transaction = try TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message))
        return Preparation(source: .local([instruction], address, fixture.configuration, fixture.blockhash),
            signer: address, transaction: transaction, network: fixture.network,
            fee: fixture.fee, simulation: fixture.simulation)
    }
}
