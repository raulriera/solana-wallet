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
        let preparationRPC = PreparationRPC(fixture: expected)
        let signingRPC = SigningRPC(fee: 15_000)
        let store = SigningRecoveryStore(recovery: recovery)
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            preparer: Preparer(rpc: preparationRPC), signer: Signer(rpc: signingRPC, store: store), submitter: Submitter(rpc: signingRPC), confirmer: Confirmer(rpc: signingRPC)
        )
        var input = expected.bytes
        input.insert(0xff, at: input.startIndex)
        input = input.dropFirst() // Exercise Foundation data with a nonzero start index.

        let preparation = try await coordinator.prepare(TransactionDecoder().decode(input), for: expected.signer)
        #expect(await store.reads.isEmpty)
        let signed = try await coordinator.sign(preparation, for: UUID(), reason: "Approve reviewed transaction")

        #expect(preparation.transaction == expected.transaction)
        #expect(preparation.bytes == input)
        #expect(preparation.signer == expected.signer)
        let reference = try ExternalFixture.signed(hasPayerSignature: hasPayerSignature)
        #expect(signed.transaction.serializedRepresentation.dropLast(64) == reference.dropLast(64))
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(reference.dropFirst(74).prefix(32)))
        #expect(key.isValidSignature(signed.transaction.serializedRepresentation.suffix(64), for: preparation.message))
        #expect(try TransactionBuilder().transaction(byAdding: reference.suffix(64), for: expected.signer, to: input).serializedRepresentation == reference)
        #expect(signed.isFullySigned == hasPayerSignature)
        #expect(await store.reads.count == 1)
        let requests = await preparationRPC.requests
        #expect(requests.count == 3)
        let validity = try #require(requests.first as? IsBlockhashValid)
        #expect(validity.blockhash == expected.transaction.lifetimeSpecifier)
        #expect(validity.commitment == .confirmed)
        #expect(validity.minContextSlot == nil)
        let simulation = try #require(requests.compactMap { $0 as? SimulateTransaction }.first)
        #expect(simulation.transaction == input)
        #expect(simulation.minContextSlot == 400)
        #expect(!simulation.verifiesSignatures && !simulation.replacesRecentBlockhash)
        let checks = await signingRPC.requests.compactMap { $0 as? IsBlockhashValid }
        #expect(checks.count == 2)
        #expect(checks.allSatisfy {
            $0.blockhash == expected.transaction.lifetimeSpecifier && $0.commitment == .confirmed && $0.minContextSlot == 402
        })
    }

    /// Verifies malformed authority cannot reach provider work or produce a review.
    ///
    /// - Parameter condition: The invalid signer role or existing signature.
    @Test("unrelated signers and invalid or occupied signature slots cannot enter review", arguments: [
        "unrelated account", "occupied slot", "invalid cosigner"
    ])
    func invalidSignaturesStopPreparation(_ condition: String) async throws {
        let expected = try ExternalFixture.preparation()
        let rpc = PreparationRPC(fixture: expected)
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

        await #expect(throws: error) { try await Preparer(rpc: rpc).prepare(TransactionDecoder().decode(input), for: signer) }

        #expect(await rpc.requests.isEmpty)
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
        let rpc = SigningRPC(fee: 15_000)
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)

        await #expect(throws: PreparationValidator.Failure.messageMismatch) {
            try await Signer(rpc: rpc, store: store).sign(preparation, for: UUID(), reason: "Approve transaction")
        }

        #expect(await rpc.requests.isEmpty)
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
        let preparationRPC = PreparationRPC(fixture: expected, blockhashValid: stage != "preparation")
        let signingRPC = SigningRPC(fee: 15_000, validities: stage == "during authentication" ? [true, false] : [stage == "stale context"],
                                    validitySlot: stage == "stale context" ? 399 : 403)
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)
        let wallet = RecordingWallet()
        let coordinator = TransactionCoordinator(preparer: Preparer(rpc: preparationRPC),
            signer: Signer(rpc: signingRPC, store: store, wallet: wallet), submitter: Submitter(rpc: signingRPC), confirmer: Confirmer(rpc: signingRPC))

        if stage == "preparation" {
            await #expect(throws: Preparer.Failure.invalidBlockhash) {
                try await coordinator.prepare(expected.transaction, for: expected.signer)
            }
            #expect(await preparationRPC.requests.count == 1)
        } else {
            let preparation = try await coordinator.prepare(expected.transaction, for: expected.signer)
            await #expect(throws: PreparationValidator.Failure.expired) {
                try await coordinator.sign(preparation, for: UUID(), reason: "Approve transaction")
            }
        }

        #expect(await wallet.messages.isEmpty)
        #expect(await store.reads.count == (stage == "during authentication" ? 1 : 0))
    }
}
