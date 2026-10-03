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
                address: Address("7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe"), index: 0),
            Account(id: UUID(), recoveryID: recoveryID, address: fixture.account.address, index: 1),
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

        #expect(await store.reads.map(\.walletID) == [recoveryID, recoveryID])
    }

    /// Rejects an unrelated address before access and a wrong index when recovering the signing key.
    /// - Parameter field: The account field that disagrees with the reviewed signer.
    @Test(arguments: ["address", "index"])
    func `A mismatched account address or index cannot sign`(_ field: String) async throws {
        let fixture = try SigningFixture()
        let account = Account(id: fixture.account.id, recoveryID: fixture.account.recoveryID,
            address: field == "address" ? fixture.transfer.accounts[1].address : fixture.account.address,
            index: field == "index" ? 0 : fixture.account.index)
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let http = try HTTPResponses.signing()
        let signer = Signer(rpc: http.client, store: store)

        await #expect(throws: SigningError.signerMismatch) {
            try await signer.sign(fixture.preparation, for: account, reason: "Approve account")
        }

        #expect(await store.reads.count == (field == "address" ? 0 : 1))
        if field == "address" { #expect(await http.requests.isEmpty) }
    }

    /// Rejects account numbers outside the hardened range before RPC or recovery access.
    /// - Parameter index: An account number that cannot form a hardened child index.
    @Test(arguments: [UInt32(0x8000_0000), UInt32.max])
    func `An invalid account index cannot unlock recovery`(_ index: UInt32) async throws {
        let fixture = try SigningFixture()
        let account = Account(id: fixture.account.id, recoveryID: fixture.account.recoveryID,
            address: fixture.account.address, index: index)
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let http = try HTTPResponses.signing()

        await #expect(throws: DerivationPath.ValidationError.invalidPath) {
            try await Signer(rpc: http.client, store: store).sign(fixture.preparation, for: account, reason: "Approve account")
        }

        #expect(await store.reads.isEmpty)
        #expect(await http.requests.isEmpty)
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
