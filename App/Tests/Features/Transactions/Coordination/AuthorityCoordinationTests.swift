import CryptoKit
import Encoding
import Foundation
import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

struct AuthorityCoordinationTests {
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")

    @Test(arguments: [true, false])
    func `The first authority pays and every authority signs its own slot`(oneTimePays: Bool) async throws {
        let fixture = try SigningFixture()
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator = try coordinator(fixture: fixture, store: store)
        let authorities: [Authority] = oneTimePays
            ? [.oneTime(fixture.oneTime), .account(fixture.account)]
            : [.account(fixture.account), .oneTime(fixture.oneTime)]

        let review = try await coordinator.simulate(instructions(fixture), using: authorities)
        let signed = try await coordinator.sign(review)

        #expect(try signed.accounts.first?.address == authorities[0].address)
        let valid = try authorities.map { authority in
            let address = try authority.address
            let index = try #require(signed.accounts.firstIndex { $0.address == address })
            let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(#require(Base58.decode(address.value, byteCount: 32))))
            return key.isValidSignature(signed.signatures[index], for: signed.message)
        }
        #expect(valid == [true, true])
        #expect(await store.reads.map(\.recoveryID) == [fixture.account.recoveryID])
    }

    @Test
    func `Submission counts one-time authorities as local signers`() async throws {
        let fixture = try SigningFixture()
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator = try coordinator(fixture: fixture, store: store)
        let review = try await coordinator.simulate(instructions(fixture),
                                                    using: [.oneTime(fixture.oneTime), .account(fixture.account)])

        let outcome = try await coordinator.submit(review)

        #expect(!outcome.signature.isEmpty)
        #expect(await store.reads.count == 1)
    }

    private func coordinator(
        fixture: SigningFixture,
        store: any RecoveryStoring
    ) throws -> any TransactionCoordinating {
        let preparation = try HTTPResponses.preparation(fixture: fixture.preparation)
        let signing = try HTTPResponses.signing()
        return TransactionCoordinator(
            rpc: signing.client, configuration: fixture.configuration, preparer: Preparer(rpc: preparation.client),
            signer: Signer(validator: PreparationValidator(rpc: signing.client), store: store),
            submitter: Submitter(rpc: HTTPResponses([:], error: Self.rateLimit).client), confirmer: Confirmer(rpc: signing.client)
        )
    }

    private func instructions(_ fixture: SigningFixture) throws -> [Instruction] {
        try [
            SystemProgram.transfer(from: fixture.account.address, to: fixture.transfer.accounts[1].address, lamports: 1),
            MemoProgram.memo("One-time authority", signers: [Address(fixture.oneTime.address)]),
        ]
    }
}
