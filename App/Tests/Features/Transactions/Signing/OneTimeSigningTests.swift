import CryptoKit
import Encoding
import Foundation
import Testing
import Transactions
import Wallet
@testable import widgets

/// Verifies one-time accounts sign reviewed bytes in memory, with the same checks as saved accounts.
struct OneTimeSigningTests {
    /// Verifies a one-time account signs the reviewed message after both lifetime checks, without recovery access.
    @Test
    func `A one-time account signs the reviewed message without reading recovery`() async throws {
        let fixture = try SigningFixture()
        let address = try Address(fixture.oneTime.address)
        let preparation = try fixture.preparation(for: address)
        let http = try HTTPResponses.signing()
        let signer = Signer(validator: PreparationValidator(rpc: http.client), store: UnavailableRecoveryStore())

        let signed = try await signer.sign(preparation, for: .oneTime(fixture.oneTime), reason: "Approve transaction")

        let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(#require(Base58.decode(address.value, byteCount: 32))))
        #expect(key.isValidSignature(signed.transaction.signatures[0], for: preparation.message))
        #expect(signed.isFullySigned)
        #expect(try await http.requests.filter { try $0.rpcMethod == "getBlockHeight" }.count == 2)
    }

    /// Verifies a one-time account can't fill another signer's slot, before any network work.
    @Test
    func `A one-time account cannot sign for another address`() async throws {
        let fixture = try SigningFixture()
        let http = try HTTPResponses.signing()
        let signer = Signer(validator: PreparationValidator(rpc: http.client), store: UnavailableRecoveryStore())

        await #expect(throws: SigningError.signerMismatch) {
            try await signer.sign(fixture.preparation, for: .oneTime(fixture.oneTime), reason: "Approve transaction")
        }

        #expect(await http.requests.isEmpty)
    }

    /// Verifies a review that expires before or after signing never yields a one-time signature.
    ///
    /// - Parameter expiresAfterSigning: Whether the first expiry check still passes.
    @Test(arguments: [false, true])
    func `An expired review never yields a one-time signature`(expiresAfterSigning: Bool) async throws {
        let fixture = try SigningFixture()
        let preparation = try fixture.preparation(for: Address(fixture.oneTime.address))
        let http = try HTTPResponses.signing(heights: expiresAfterSigning ? [500, 551] : [551])
        let signer = Signer(validator: PreparationValidator(rpc: http.client), store: UnavailableRecoveryStore())

        await #expect(throws: PreparationValidatorError.expired) {
            try await signer.sign(preparation, for: .oneTime(fixture.oneTime), reason: "Approve transaction")
        }
    }
}
