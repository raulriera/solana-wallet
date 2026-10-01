import CryptoKit
import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies external V1 bytes use the shared app review and signing boundary.
struct ExternalTransactionTests {
    /// Verifies signing a non-payer slot preserves the original message and other slots.
    ///
    /// - Parameter hasPayerSignature: Whether the result completes all required signatures.
    @Test("a wallet cosigner preserves supplied bytes and existing signatures", arguments: [true, false])
    func signingPreservesExternalTransaction(hasPayerSignature: Bool) async throws {
        let expected = try ExternalFixture.preparation(hasPayerSignature: hasPayerSignature)
        let recovery = try SigningFixture().recovery
        let preparationHTTP = try HTTPResponses.preparation(fixture: expected)
        let signingHTTP = try HTTPResponses.signing(fee: 15_000)
        let store = SigningRecoveryStore(recovery: recovery)
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            rpc: preparationHTTP.client, preparer: Preparer(rpc: preparationHTTP.client), signer: Signer(rpc: signingHTTP.client, store: store), submitter: Submitter(rpc: signingHTTP.client), confirmer: Confirmer(rpc: signingHTTP.client)
        )
        var input = expected.bytes
        input.insert(0xff, at: input.startIndex)
        input = input.dropFirst() // Exercise Foundation data with a nonzero start index.

        let preparation = try await coordinator.simulate(TransactionDecoder().decode(input), using: SigningFixture().account)
        #expect(await store.reads.isEmpty)
        let signed = try await coordinator.sign(preparation)

        #expect(preparation.transaction == expected.transaction)
        #expect(preparation.lastValidBlockHeight == nil)
        #expect(preparation.transaction.serializedRepresentation == input)
        let reference = try ExternalFixture.signed(hasPayerSignature: hasPayerSignature)
        #expect(signed.serializedRepresentation.dropLast(64) == reference.dropLast(64))
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(reference.dropFirst(74).prefix(32)))
        #expect(key.isValidSignature(signed.serializedRepresentation.suffix(64), for: preparation.transaction.message))
        #expect(try TransactionBuilder().transaction(byAdding: reference.suffix(64), for: expected.signer, to: input).serializedRepresentation == reference)
        #expect(signed.signatures.allSatisfy { $0.contains(where: { $0 != 0 }) } == hasPayerSignature)
        #expect(await store.reads.count == 1)
        let requests = await preparationHTTP.requests
        #expect(requests.count == 3)
        let validity = try #require(requests.first).rpcParameters
        #expect(validity[0] as? String == expected.transaction.lifetimeSpecifier)
        let simulation = try #require(requests.first { try $0.rpcMethod == "simulateTransaction" }).rpcParameters
        #expect(simulation[0] as? String == input.base64EncodedString())
        let checks = try await signingHTTP.requests.filter { try $0.rpcMethod == "isBlockhashValid" }
        #expect(checks.count == 2)
        for check in checks {
            let parameters = try check.rpcParameters
            #expect(parameters[0] as? String == expected.transaction.lifetimeSpecifier)
            #expect((parameters[1] as? [String: Any])?["minContextSlot"] as? Int == 402)
        }
    }

    /// Verifies malformed authority cannot reach provider work or produce a review.
    ///
    /// - Parameter condition: The invalid signer role or existing signature.
    @Test("unrelated signers and invalid or occupied signature slots cannot enter review", arguments: [
        "unrelated account", "occupied slot", "invalid cosigner"
    ])
    func invalidSignaturesStopPreparation(_ condition: String) async throws {
        let expected = try ExternalFixture.preparation()
        let http = try HTTPResponses.preparation(fixture: expected)
        var input = expected.bytes
        var signer = expected.signer
        let error: ValidationError
        switch condition {
        case "unrelated account":
            signer = try #require(expected.transaction.accounts.last).address
            error = .signerNotRequired
        case "occupied slot":
            input = try ExternalFixture.signed()
            error = .signatureAlreadyPresent
        default:
            input[input.count - 128] ^= 1
            error = .invalidSignature
        }

        await #expect(throws: error) { try await Preparer(rpc: http.client).prepare(TransactionDecoder().decode(input), for: signer) }

        #expect(await http.requests.isEmpty)
    }

    /// Verifies displayed instruction and account metadata must match the exact signed bytes.
    ///
    /// - Parameter field: The decoded field altered independently of its message.
    @Test("altered external inspection details cannot unlock recovery", arguments: ["instructions", "privileges", "lifetime"])
    func alteredInspectionCannotUnlockRecovery(_ field: String) async throws {
        let expected = try ExternalFixture.preparation()
        let original = expected.transaction
        var accounts = original.accounts
        if field == "privileges" {
            let account = accounts[1]
            accounts[1] = .init(address: account.address, isSigner: true, isWritable: !account.isWritable)
        }
        let altered = Transaction(
            message: original.message, lifetimeSpecifier: field == "lifetime" ? "altered" : original.lifetimeSpecifier,
            accounts: accounts, requests: original.requests,
            instructions: field == "instructions" ? [] : original.instructions, signatures: original.signatures
        )
        let preparation = Preparation(source: expected.source, signer: expected.signer, transaction: altered,
                                      network: expected.network, fee: expected.fee, simulation: expected.simulation)
        let http = try HTTPResponses.signing(fee: 15_000)
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)

        await #expect(throws: PreparationValidator.Failure.messageMismatch) {
            try await Signer(rpc: http.client, store: store).sign(preparation, for: SigningFixture().account, reason: "Approve transaction")
        }

        #expect(await http.requests.isEmpty)
        #expect(await store.reads.isEmpty)
    }

    /// Verifies unknown, expired, or stale blockhash observations cannot reach the wallet signer.
    ///
    /// - Parameter stage: The point at which the supplied blockhash becomes unusable.
    @Test("an unavailable external blockhash stops signing without substitution", arguments: [
        "preparation", "before authentication", "during authentication", "stale context"
    ])
    func invalidBlockhashPreventsSigning(_ stage: String) async throws {
        let expected = try ExternalFixture.preparation()
        let preparationHTTP = try HTTPResponses.preparation(fixture: expected, blockhashValid: stage != "preparation")
        let signingHTTP = try HTTPResponses.signing(fee: 15_000, validities: stage == "during authentication" ? [true, false] : [stage == "stale context"],
                                    validitySlot: stage == "stale context" ? 399 : 403)
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)
        let wallet = RecordingWallet()
        let coordinator = TransactionCoordinator(rpc: preparationHTTP.client, preparer: Preparer(rpc: preparationHTTP.client),
            signer: Signer(rpc: signingHTTP.client, store: store, wallet: wallet), submitter: Submitter(rpc: signingHTTP.client), confirmer: Confirmer(rpc: signingHTTP.client))

        if stage == "preparation" {
            await #expect(throws: Preparer.Failure.invalidBlockhash) {
                try await coordinator.simulate(expected.transaction, using: SigningFixture().account)
            }
            #expect(await preparationHTTP.requests.count == 1)
        } else {
            let preparation = try await coordinator.simulate(expected.transaction, using: SigningFixture().account)
            await #expect(throws: PreparationValidator.Failure.expired) {
                try await coordinator.sign(preparation)
            }
        }

        #expect(await wallet.messages.isEmpty)
        #expect(await store.reads.count == (stage == "during authentication" ? 1 : 0))
    }
}
